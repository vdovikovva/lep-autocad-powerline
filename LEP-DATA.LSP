
;=====================================================================
;
;   ПРОЕКТ:      LEP
;   ФАЙЛ:        LEP-DATA.LSP
;   ВЕРСИЯ:      1.0  (LEP:AddKtpData - данные наземной КТП, Claude,
;                2026-07-22)
;   0.9  (LEP:SetSpanLabelHandle - для объединения подписей
;                соседних пролётов одной марки/типа; ReassignSpanRoute
;                сохраняет новые поля пролёта (RAWLENGTH/POLE1HANDLE/
;                POLE2HANDLE/LABELHANDLE/METHOD), Claude, 2026-07-22)
;   0.8  (LEP:ReassignRoute - массовая перепривязка опор/
;                пролётов на другой RouteID, Claude, 2026-07-16)
;   0.7  (LEP:AddEquipToExistingPole - оборудование на
;                СУЩЕСТВУЮЩЕЙ опоре, не перезаписывая её XDATA, Claude,
;                2026-07-15)
;   0.6  (LEP:AddEquipData - честный STATUS оконечного
;                оборудования, Claude, 2026-07-15)
;   0.5  (номер маршрута из чертежа + честный STATUS опоры
;                - аудит Claude Fable, 2026-07-11)
;
;   ИСПРАВЛЕНО В ЭТОЙ ВЕРСИИ:
;   LEP:SetData записывала данные НЕПРАВИЛЬНЫМ форматом XDATA — пары
;   (1000 . "...") и (1001 . "...") добавлялись "плоско", верхним
;   уровнем прямо в список сущности. AutoCAD ожидает, что вся XDATA
;   одного приложения обёрнута в ОДНУ группу с кодом -3, внутри
;   которой первым элементом идёт имя приложения, а дальше — сами
;   данные. Правильная структура:
;
;     (-3 ("LEP_DATA" (1000 . "TYPE=ROUTE") (1000 . "ID=...") ...))
;
;   Из-за старой (неправильной) записи LEP:GetData не могла найти
;   данные при чтении — а на ней держится вся связка "трасса -> опоры
;   -> ведомость". Теперь формат исправлен и в SetData, и в GetData.
;
;   ДОБАВЛЕНА новая функция LEP:GetDataValue — читает значение по
;   имени ключа (например "ID"), а не по номеру позиции в списке,
;   как было раньше в LEP-POLE.LSP (это было хрупко: любое изменение
;   порядка полей ломало чтение).
;
;   НАЗНАЧЕНИЕ:
;   Хранение данных объектов проекта LEP (маршруты, опоры и т.д.)
;   внутри самого DWG через XDATA.
;
;   Каждый объект получает набор параметров, например:
;   TYPE, STATUS, MODEL, ROUTE, ID.
;
;=====================================================================
 
 
;=====================================================================
;                       НАСТРОЙКИ
;=====================================================================
 
(setq *LEP-RegApp* "LEP_DATA")

;; *LEP-RouteCounter* больше НЕ инициализируется здесь и не является
;; источником истины (⚠️ ФИКС 2026-07-11): раньше счётчик жил только в
;; памяти AutoCAD - после закрытия и повторного открытия чертежа он
;; сбрасывался в 1, и новый маршрут получал ID "LEP_ROUTE_01", который
;; УЖЕ существовал на чертеже. Два разных маршрута с одинаковым ID
;; МОЛЧА сливались в один блок в ведомости (метраж и опоры двух разных
;; заявителей суммировались без какого-либо предупреждения). Теперь
;; номер всегда выводится из САМОГО ЧЕРТЕЖА - см. LEP:GetMaxRouteNumber
;; ниже; переменная осталась только для отладки (!*LEP-RouteCounter*
;; в консоли показывает последний выданный номер).
 
 
;=====================================================================
;
; LEP:RegisterApp
;
; Регистрация имени приложения для XDATA.
; AutoCAD требует, чтобы имя было заранее зарегистрировано командой
; regapp, иначе entmod с XDATA этого приложения будет отклонён.
;
;=====================================================================
 
(defun LEP:RegisterApp (/)
    (if (not (tblsearch "APPID" *LEP-RegApp*))
        (regapp *LEP-RegApp*)
    )
)
 
 
;=====================================================================
;
; LEP:GetMaxRouteNumber
;
; Наибольший номер маршрута, РЕАЛЬНО существующего на чертеже - для
; LEP:CreateRouteID ниже (⚠️ ФИКС 2026-07-11, см. комментарий у
; *LEP-RouteCounter* в начале файла: раньше номер брался из счётчика
; в памяти, который сбрасывался при перезапуске AutoCAD, и ID
; дублировались - теперь номер всегда выводится из самого чертежа).
;
; Сканируются все полилинии на слое маршрутов, из XDATA читается ID
; ("LEP_ROUTE_NN"), берётся максимальный номер. Слой маршрутов может
; быть выключен (LEP-ROUTEVIS) - на время сканирования временно
; включается и возвращается обратно: тот же приём, что уже работает в
; LEP:FindNearestRoute (LEP-POLE.LSP). Единственное отличие: если
; слой маршрутов сейчас ТЕКУЩИЙ (так и есть во время C:LEP-ROUTE -
; она сама переключается на него перед PLINE), выключать его обратно
; нельзя ("-layer Off" на текущем слое задаёт дополнительный вопрос
; Yes/No и ломает заготовленную очередь аргументов command - тот же
; класс граблей, что уже ловили на LEADER/-linetype) - в этом случае
; слой просто остаётся включённым.
;
;=====================================================================

(defun LEP:GetMaxRouteNumber (/ LayerData WasOff SS i Ent ID Num MaxNum)

    (setq MaxNum 0)

    (setq LayerData (tblsearch "LAYER" *LEP-Layer-Route*))
    (setq WasOff (and LayerData (< (cdr (assoc 62 LayerData)) 0)))
    (if WasOff
        (command "_.-layer" "_On" *LEP-Layer-Route* "")
    )

    (setq SS (ssget "_X" (list '(0 . "LWPOLYLINE") (cons 8 *LEP-Layer-Route*))))

    (if SS
        (progn
            (setq i 0)
            (repeat (sslength SS)
                (setq Ent (ssname SS i))
                (setq ID (LEP:GetDataValue Ent "ID"))
                ;; Формат ID - "LEP_ROUTE_NN": префикс "LEP_ROUTE_" -
                ;; это 10 символов, номер начинается с 11-го. atoi
                ;; спокойно переваривает ведущий ноль ("07" -> 7), а на
                ;; мусоре возвращает 0 - т.е. чужой/битый ID просто не
                ;; влияет на максимум, а не роняет команду.
                (if ID
                    (progn
                        (setq Num (atoi (substr ID 11)))
                        (if (> Num MaxNum) (setq MaxNum Num))
                    )
                )
                (setq i (1+ i))
            )
        )
    )

    (if (and WasOff (/= (getvar "CLAYER") *LEP-Layer-Route*))
        (command "_.-layer" "_Off" *LEP-Layer-Route* "")
    )

    MaxNum
)


;=====================================================================
;
; LEP:CreateRouteID
;
; Создание уникального номера маршрута вида "LEP_ROUTE_01".
;
; Номер = максимальный номер существующего на чертеже маршрута + 1
; (см. LEP:GetMaxRouteNumber выше) - НЕ счётчик в памяти (⚠️ ФИКС
; 2026-07-11, история в комментарии у *LEP-RouteCounter*).
;
; Было 4 цифры ("LEP_ROUTE_0001") - сократили до 2 (по просьбе
; пользователя: больше 99 маршрутов на одном чертеже не бывает, а
; короче номер - меньше визуального шума в подписи на чертеже, см.
; LEP:CreateRouteLabel в LEP-ROUTE.LSP). Если когда-нибудь маршрутов
; станет больше 99 - ничего не сломается, просто номер станет длиннее
; ("100" и т.д.), т.к. substr всегда берёт последние 2 символа от
; строки с ведущими нулями.
;=====================================================================

(defun LEP:CreateRouteID (/ Num NumStr ID)

    (setq Num (1+ (LEP:GetMaxRouteNumber)))
    (setq *LEP-RouteCounter* Num) ; только для отладки, не источник истины

    (setq NumStr (strcat "00" (itoa Num)))
    (setq ID
        (strcat
            "LEP_ROUTE_"
            (substr NumStr (- (strlen NumStr) 1))
        )
    )

    ID
)
 
 
;=====================================================================
;
; LEP:SetData  (ИСПРАВЛЕНО)
;
; Записывает данные в объект в виде XDATA.
;
; Формат входных данных:
; (
;  ("TYPE" . "POLE")
;  ("MODEL" . "П20-3Н")
;  ("STATUS" . "PROJECT")
; )
;
; Каждая пара превращается в строку "КЛЮЧ=ЗНАЧЕНИЕ" и кладётся как
; отдельная группа (1000 . "КЛЮЧ=ЗНАЧЕНИЕ") ВНУТРИ единственной
; группы -3, как того требует AutoCAD.
;
;=====================================================================
 
(defun LEP:SetData (Ent DataList / NewXdataList Item)
 
    (LEP:RegisterApp)
 
    ;; Собираем список пар (1000 . "КЛЮЧ=ЗНАЧЕНИЕ")
    (setq NewXdataList nil)
    (foreach Item DataList
        (setq NewXdataList
            (append
                NewXdataList
                (list
                    (cons 1000 (strcat (car Item) "=" (cdr Item)))
                )
            )
        )
    )
 
    ;; ПРАВИЛЬНАЯ структура XDATA:
    ;;   (-3 ("LEP_DATA" (1000 . "...") (1000 . "...") ...))
    ;; (cons *LEP-RegApp* NewXdataList) собирает список, где первый
    ;; элемент - имя приложения (строка), а дальше - пары данных.
    (entmod
        (append
            (entget Ent)
            (list
                (list -3 (cons *LEP-RegApp* NewXdataList))
            )
        )
    )
 
    (entupd Ent)
)
 
 
;=====================================================================
;
; LEP:GetData  (ИСПРАВЛЕНО)
;
; Читает "сырые" данные объекта (список строк "КЛЮЧ=ЗНАЧЕНИЕ").
;
; Возвращает список строк, например:
; ("TYPE=ROUTE" "ID=LEP_ROUTE_0001" "STATUS=PROJECT")
;
; Обычно удобнее пользоваться LEP:GetDataValue (см. ниже) - она сразу
; отдаёт значение по конкретному ключу.
;
;=====================================================================
 
(defun LEP:GetData (Ent / RawXdata AppBlock Result Item)
 
    (setq Result nil)
 
    ;; entget с явным именем приложения возвращает ОДНУ группу -3.
    ;; Её структура: (-3 ("LEP_DATA" (1000 . "...") (1000 . "...") ...))
    (setq RawXdata (assoc -3 (entget Ent (list *LEP-RegApp*))))
 
    (if RawXdata
        (progn
            ;; (cdr RawXdata) = ( ("LEP_DATA" (1000 . "...") ...) )
            ;; -- список из ОДНОГО элемента, поэтому берём (car ...)
            ;; AppBlock = ("LEP_DATA" (1000 . "...") (1000 . "...") ...)
            (setq AppBlock (car (cdr RawXdata)))
 
            ;; (cdr AppBlock) пропускает имя приложения, оставляя
            ;; только пары (1000 . "...")
            (foreach Item (cdr AppBlock)
                (if (= (car Item) 1000)
                    (setq Result (append Result (list (cdr Item))))
                )
            )
        )
    )
 
    Result
)
 
 
;=====================================================================
;
; LEP:GetDataValue  (НОВАЯ ФУНКЦИЯ)
;
; Возвращает значение одного конкретного ключа (например "ID"),
; либо nil, если такого ключа нет.
;
; Раньше в LEP-POLE.LSP RouteID доставали вручную через
; (nth 2 (car (cdr RouteData))) - то есть "третий элемент списка".
; Это ломалось при любом изменении порядка полей. Теперь ищем
; строго по имени ключа - надёжно при любом порядке.
;
; Пример использования:
;   (LEP:GetDataValue RouteEnt "ID")  -> "LEP_ROUTE_0001"
;
;=====================================================================
 
(defun LEP:GetDataValue (Ent Key / KeyLen Item Result)
 
    (setq Result nil)
    (setq KeyLen (strlen Key))
 
    (foreach Item (LEP:GetData Ent)
        ;; Ищем строки вида "КЛЮЧ=ЗНАЧЕНИЕ", у которых начало точно
        ;; совпадает с Key, а сразу после него идёт знак "="
        (if (and (> (strlen Item) KeyLen)
                 (= (substr Item 1 KeyLen) Key)
                 (= (substr Item (1+ KeyLen) 1) "=")
            )
            (setq Result (substr Item (+ KeyLen 2)))
        )
    )
 
    Result
)
 
 
;=====================================================================
;
; LEP:AddRoute
;
; Записывает данные нового маршрута. VClass - код класса напряжения
; ("10" или "04", см. *LEP-VoltageClasses* в LEP-CONFIG.LSP) -
; спрашивается один раз при построении маршрута (LEP-ROUTE.LSP) и
; хранится здесь же, в XDATA маршрута (ключ VCLASS) - дальше LEP-SPAN
; и LEP-POLE читают его через (LEP:GetDataValue RouteEnt "VCLASS"),
; чтобы предложить нужный список марок провода и вторую строку
; подписи опоры, не спрашивая класс заново на каждом пролёте/опоре.
;
;=====================================================================

(defun LEP:AddRoute (Ent VClass / ID)

    (setq ID (LEP:CreateRouteID))

    (LEP:SetData
        Ent
        (list
            (cons "TYPE" "ROUTE")
            (cons "ID" ID)
            (cons "STATUS" "PROJECT")
            (cons "VCLASS" VClass)
        )
    )

    ID
)
 
 
;=====================================================================
;
; LEP:AddPoleData
;
; Запись данных опоры (тип, статус, привязка к маршруту).
;
; ⚠️ ФИКС 2026-07-11: добавлен параметр Status. Раньше в XDATA ВСЕГДА
; писалось "STATUS=PROJECT" - даже для опоры, которую пользователь
; пометил как существующую (Сущ.). Ошибка была ЗАМАСКИРОВАНА тем, что
; ведомость (LEP-REPORT) фильтрует опоры по СЛОЮ (существующие лежат
; на LEP-EXIST-POLES и в скан вообще не попадают) - но сами данные в
; XDATA врали, и любой будущий код, который поверил бы ключу STATUS,
; посчитал бы существующую опору как проектируемую. Теперь статус
; передаётся реальный ("PROJECT"/"EXIST" - тот же, что определяет слой).
;
; ⚠️ ФИКС 2026-07-15: добавлен параметр LabelEnt - хендл подписи-
; выноски этой опоры сохраняется в XDATA ключом LABELHANDLE. Нужно для
; LEP-POLE-DELETE/LEP-POLE-MOVE (LEP-POLE.LSP) - подпись создаётся
; ОТДЕЛЬНЫМ объектом (MLEADER), никак не связанным с блоком опоры в
; базе AutoCAD, поэтому без явно сохранённого хендла её было бы нечем
; найти при удалении/переносе опоры - осталась бы висеть в воздухе,
; указывая на пустое место (проверено живым тестом 2026-07-15:
; entdel опоры НЕ трогает подпись - это ожидаемо и подтверждено).
; Хендл (не ename!) - потому что ename не переживает закрытие/открытие
; чертежа, а хендл - переживает, entity handle через (handent ...)
; всегда можно превратить обратно в ename в текущей сессии.
;
;=====================================================================

(defun LEP:AddPoleData (Ent RouteID PoleType Status LabelEnt)

    (LEP:SetData
        Ent
        (list
            (cons "TYPE" "POLE")
            (cons "ROUTE" RouteID)
            (cons "MODEL" PoleType)
            (cons "STATUS" Status)
            (cons "LABELHANDLE" (cdr (assoc 5 (entget LabelEnt))))
        )
    )

)


;=====================================================================
;
; LEP:AddEquipData
;
; То же самое, что LEP:AddPoleData, плюс ДОПОЛНИТЕЛЬНЫЙ ключ EQUIP -
; что именно на этой опоре подписано ("RLK"/"MTP"/"SCHU"/"PU"). Сама
; опора и так попадает в обычный подсчёт по MODEL (LEP-REPORT, без
; изменений) - EQUIP нужен отдельно, чтобы посчитать в ведомости само
; оборудование (РЛК/МТП/ЩУ/ПУ), а не только опоры, на которых оно
; висит.
;
; ⚠️ ФИКС 2026-07-15: добавлен параметр Status (раньше, как и когда-то
; у LEP:AddPoleData, было зашито "STATUS=PROJECT" всегда - но иногда
; нужно нарисовать СУЩЕСТВУЮЩЕЕ оконечное оборудование, не только
; проектируемое, чтобы оно не попадало в ведомость проектируемых
; материалов). Статус теперь спрашивается в C:LEP-END (LEP-END.LSP,
; LEP:GetStatus - та же общая функция, что у обычных опор в LEP-POLE)
; и передаётся сюда честно.
;
;=====================================================================

(defun LEP:AddEquipData (Ent RouteID PoleType EquipCode Status)

    (LEP:SetData
        Ent
        (list
            (cons "TYPE" "POLE")
            (cons "ROUTE" RouteID)
            (cons "MODEL" PoleType)
            (cons "STATUS" Status)
            (cons "EQUIP" EquipCode)
        )
    )

)


;=====================================================================
;
; LEP:AddEquipToExistingPole
;
; Добавляет оборудование (например ПУ) на УЖЕ СУЩЕСТВУЮЩУЮ опору -
; 2026-07-15, по просьбе пользователя ("не плодить новую опору ради
; ПУ, если подключение реально идёт к уже стоящей"). Опора при этом
; остаётся ровно тем, чем была (та же трапеция, тот же статус Сущ.) -
; НЕ через LEP:AddEquipData, которая полностью ПЕРЕЗАПИСЫВАЕТ XDATA
; объекта (см. LEP:SetData выше - пишет ЦЕЛИКОМ новый набор ключей,
; ничего старого не сохраняя). Если бы вызвали LEP:AddEquipData на
; существующей опоре - она потеряла бы свой LABELHANDLE (нечем было бы
; найти её подпись для LEP-POLE-DELETE/MOVE) и, что хуже, получила бы
; STATUS того оборудования, которое добавляем (обычно "PROJECT") -
; опора визуально осталась бы Сущ. (слой не меняется), но ЛГАЛА бы в
; XDATA, что она новая - тот же класс ошибки, что когда-то ловили и
; чинили в LEP:AddPoleData.
;
; Поэтому здесь - читаем ВСЕ существующие поля опоры и переписываем их
; же обратно, ДОБАВИВ EQUIP и EQUIPSTATUS (статус именно ОБОРУДОВАНИЯ,
; отдельно от статуса самой опоры - опора Сущ., а ПУ на ней - Проект.,
; это НЕ противоречие, а как раз тот самый случай, ради которого вся
; эта функция).
;
; ⚠️ LEP-REPORT.LSP должен знать про EQUIPSTATUS отдельно от STATUS -
; см. отдельный скан слоя существующих опор там же.
;
;=====================================================================

(defun LEP:AddEquipToExistingPole (PoleEnt EquipCode EquipStatus / Type Route Model Status LabelHandle)

    (setq Type        (LEP:GetDataValue PoleEnt "TYPE"))
    (setq Route       (LEP:GetDataValue PoleEnt "ROUTE"))
    (setq Model       (LEP:GetDataValue PoleEnt "MODEL"))
    (setq Status      (LEP:GetDataValue PoleEnt "STATUS"))
    (setq LabelHandle (LEP:GetDataValue PoleEnt "LABELHANDLE"))

    (LEP:SetData
        PoleEnt
        (list
            (cons "TYPE" Type)
            (cons "ROUTE" Route)
            (cons "MODEL" Model)
            (cons "STATUS" Status)
            (cons "LABELHANDLE" LabelHandle)
            (cons "EQUIP" EquipCode)
            (cons "EQUIPSTATUS" EquipStatus)
        )
    )

)


;=====================================================================
;
; LEP:AddKtpData
;
; Данные наземной КТП (2026-07-22) - НЕ опора, свой набор ключей: TYPE
; "KTP" (не "POLE" - LEP-REPORT.LSP сканирует её отдельным этапом).
; Number/Power/Marka - свободный ввод пользователя (нет фиксированного
; списка, в отличие от МТП/СТП - см. LEP-CONFIG.LSP).
;
; ⚠️ ИСПРАВЛЕНО В КОММЕНТАРИИ 2026-07-24: здесь раньше было написано,
; что "LEP:PickPole/LEP-SPAN не должны принимать КТП за опору пролёта".
; Это БОЛЬШЕ НЕ ВЕРНО - с 2026-07-24 кабельный пролёт может начинаться
; и заканчиваться на КТП или кабельном киоске (реальный случай: КТП ->
; два кабеля 0,4 кВ -> киоск с двумя ПУ, опор нет вообще).
; LEP:PickPole теперь принимает TYPE = POLE/KTP/KK, см. LEP-SPAN.LSP.
;
; HighSide - класс ВЫСОКОЙ стороны КТП ("10"/"6", *LEP-KTP-HighSide*).
; Хранится отдельным ключом, а НЕ берётся из класса маршрута: КТП -
; граница двух классов (на входе 10/6 кВ, на выходе 0,4 кВ), и трасса
; от неё к заявителю вполне может быть 0,4 кВ - тогда класс маршрута
; про высокую сторону не говорит вообще ничего.
;
;=====================================================================

(defun LEP:AddKtpData (Ent RouteID Status Number Power Marka HighSide)

    (LEP:SetData
        Ent
        (list
            (cons "TYPE" "KTP")
            (cons "ROUTE" RouteID)
            (cons "STATUS" Status)
            (cons "NUMBER" Number)
            (cons "POWER" Power)
            (cons "MARKA" Marka)
            (cons "HIGHSIDE" HighSide)
        )
    )

)


;=====================================================================
;
; LEP:AddKkData
;
; Данные кабельного киоска (КК, 2026-07-24) - тоже НЕ опора, свой
; TYPE = "KK". Устроен по образцу LEP:AddKtpData выше.
;
; Number  - номер киоска (свободный ввод, может быть пустой строкой -
;           не у всех киосков вообще есть номер на плане).
; PuCount - СКОЛЬКО приборов учёта стоит внутри киоска. Отдельными
;           объектами ПУ не рисуются СОЗНАТЕЛЬНО: внутри киоска они
;           ничем на плане не отличаются друг от друга, показывать там
;           нечего - в ведомость они попадают просто числом штук (см.
;           ЭТАП 2.6 в LEP-REPORT.LSP). Хранится СТРОКОЙ, как и все
;           остальные значения XDATA в этом проекте (XDATA у нас
;           везде текстовая, число разбирается через atoi при чтении).
;
;=====================================================================

(defun LEP:AddKkData (Ent RouteID Status Number PuCount)

    (LEP:SetData
        Ent
        (list
            (cons "TYPE" "KK")
            (cons "ROUTE" RouteID)
            (cons "STATUS" Status)
            (cons "NUMBER" Number)
            (cons "PUCOUNT" PuCount)
        )
    )

)


;=====================================================================
;
; LEP:ReassignPoleRoute / LEP:ReassignSpanRoute / LEP:ReassignRoute
;
; Массовая перепривязка объектов с ОДНОГО RouteID на ДРУГОЙ - нужно,
; когда сама трасса когда-то осталась без ID (например, сорвался
; LEP-ROUTE - см. известный баг с Shift+ПКМ во время PLINE, README) и
; все опоры/пролёты, поставленные ДО ручного исправления ID трассы,
; успели записать в СВОЮ XDATA старый, фиктивный "LEP_ROUTE_UNKNOWN" -
; 2026-07-16, по просьбе пользователя (в ведомости так и остался
; отдельный блок "LEP_ROUTE_UNKNOWN" даже после того, как саму трассу
; починили вручную через LEP:AddRoute).
;
; ⚠️ ПОЧЕМУ ЭТО ВООБЩЕ НУЖНО - ROUTE у опоры/пролёта это НЕ живая
; ссылка на трассу, а СНИМОК ID на момент создания объекта (строка в
; XDATA) - почини трассу как угодно потом, уже готовые опоры/пролёты
; сами по себе не узнают об этом, у каждого своя, отдельная копия
; старого значения. Раньше чинили по одному объекту вручную через
; консоль - при большом количестве это утомительно, отсюда весь этот
; блок.
;
; ⚠️ ПОЧЕМУ ДВЕ РАЗНЫЕ ФУНКЦИИ (Pole/Span), А НЕ ОДНА ОБЩАЯ - у опоры
; и у пролёта РАЗНЫЙ набор ключей XDATA (опора: TYPE/ROUTE/MODEL/
; STATUS/LABELHANDLE[/EQUIP/EQUIPSTATUS]; пролёт: TYPE/ROUTE/STATUS/
; WIRE/SECTION/LENGTH) - LEP:SetData ПЕРЕЗАПИСЫВАЕТ XDATA целиком (см.
; выше), значит нужно явно перечислить и сохранить ВСЕ поля нужного
; типа объекта, а не только ROUTE - тот же принцип, что уже применён в
; LEP:AddEquipToExistingPole.
;
;=====================================================================

(defun LEP:ReassignPoleRoute (Ent NewRouteID / Type Model Status LabelHandle EquipCode EquipStatus DataList)

    (setq Type        (LEP:GetDataValue Ent "TYPE"))
    (setq Model       (LEP:GetDataValue Ent "MODEL"))
    (setq Status      (LEP:GetDataValue Ent "STATUS"))
    (setq LabelHandle (LEP:GetDataValue Ent "LABELHANDLE"))
    (setq EquipCode   (LEP:GetDataValue Ent "EQUIP"))
    (setq EquipStatus (LEP:GetDataValue Ent "EQUIPSTATUS"))

    (setq DataList
        (list
            (cons "TYPE" Type)
            (cons "ROUTE" NewRouteID)
            (cons "MODEL" Model)
            (cons "STATUS" Status)
        )
    )
    ;; LABELHANDLE/EQUIP/EQUIPSTATUS - НЕ у каждой опоры есть (обычная
    ;; опора без оборудования на ней не имеет EQUIP/EQUIPSTATUS) -
    ;; дописываем только если реально были, а не пустой строкой поверх.
    (if LabelHandle (setq DataList (append DataList (list (cons "LABELHANDLE" LabelHandle)))))
    (if EquipCode   (setq DataList (append DataList (list (cons "EQUIP" EquipCode)))))
    (if EquipStatus (setq DataList (append DataList (list (cons "EQUIPSTATUS" EquipStatus)))))

    (LEP:SetData Ent DataList)
)


(defun LEP:ReassignSpanRoute (Ent NewRouteID / Status Wire Section Length RawLength Reserve Pole1 Pole2 LabelHandle Method DataList)

    (setq Status     (LEP:GetDataValue Ent "STATUS"))
    (setq Wire       (LEP:GetDataValue Ent "WIRE"))
    (setq Section    (LEP:GetDataValue Ent "SECTION"))
    (setq Length     (LEP:GetDataValue Ent "LENGTH"))
    (setq RawLength  (LEP:GetDataValue Ent "RAWLENGTH"))
    (setq Reserve    (LEP:GetDataValue Ent "RESERVE"))
    (setq Pole1      (LEP:GetDataValue Ent "POLE1HANDLE"))
    (setq Pole2      (LEP:GetDataValue Ent "POLE2HANDLE"))
    (setq LabelHandle (LEP:GetDataValue Ent "LABELHANDLE"))
    (setq Method     (LEP:GetDataValue Ent "METHOD"))

    (setq DataList
        (list
            (cons "TYPE" "SPAN")
            (cons "ROUTE" NewRouteID)
            (cons "STATUS" Status)
            (cons "WIRE" Wire)
            (cons "SECTION" Section)
            (cons "LENGTH" Length)
        )
    )
    ;; Поля, добавленные позже (2026-07-22 - объединение подписей
    ;; пролётов/способ прокладки КЛ) - не у КАЖДОГО пролёта они есть
    ;; (старые пролёты, нарисованные до этой правки, их не имеют) -
    ;; дописываем только если реально были, тем же приёмом, что уже
    ;; используется чуть выше для LABELHANDLE/EQUIP у опор.
    (if RawLength   (setq DataList (append DataList (list (cons "RAWLENGTH" RawLength)))))
    (if Reserve     (setq DataList (append DataList (list (cons "RESERVE" Reserve)))))
    (if Pole1       (setq DataList (append DataList (list (cons "POLE1HANDLE" Pole1)))))
    (if Pole2       (setq DataList (append DataList (list (cons "POLE2HANDLE" Pole2)))))
    (if LabelHandle (setq DataList (append DataList (list (cons "LABELHANDLE" LabelHandle)))))
    (if Method      (setq DataList (append DataList (list (cons "METHOD" Method)))))

    (LEP:SetData Ent DataList)
)


;=====================================================================
;
; LEP:SetSpanLabelHandle
;
; Переписывает XDATA пролёта, меняя ТОЛЬКО LABELHANDLE - остальные
; поля читаются и записываются обратно как есть (тот же приём
; "прочитать всё - переписать всё же самое + одно новое/изменённое
; поле", что уже применяется в LEP:AddEquipToExistingPole/
; LEP:ReassignSpanRoute выше - LEP:SetData ПЕРЕЗАПИСЫВАЕТ XDATA
; целиком, значит частичное обновление одного поля без этого приёма
; стёрло бы остальные).
;
; Нужна для объединения подписей соседних пролётов одной марки/типа
; (LEP-SPAN.LSP, 2026-07-22, по просьбе пользователя): когда несколько
; пролётов сливаются в одну общую подпись, ВСЕМ им нужно переписать
; LABELHANDLE на хендл этой новой общей подписи (не только вновь
; создаваемому пролёту).
;
;=====================================================================

(defun LEP:SetSpanLabelHandle (Ent NewLabelHandle / Status Wire Section Length RawLength Reserve Pole1 Pole2 Method RouteID)

    (setq RouteID    (LEP:GetDataValue Ent "ROUTE"))
    (setq Status     (LEP:GetDataValue Ent "STATUS"))
    (setq Wire       (LEP:GetDataValue Ent "WIRE"))
    (setq Section    (LEP:GetDataValue Ent "SECTION"))
    (setq Length     (LEP:GetDataValue Ent "LENGTH"))
    (setq RawLength  (LEP:GetDataValue Ent "RAWLENGTH"))
    ;; ⚠️ ДОБАВЛЕНО 2026-07-24 - и это НЕ мелочь: эта функция вызывается
    ;; ПОСЛЕ КАЖДОГО объединения подписей, то есть практически у каждого
    ;; пролёта сразу после создания. Забудь её здесь - и ключ RESERVE
    ;; (метры концевых заделок, поконцовый расчёт) стирался бы через
    ;; секунду после того, как его записали, а подпись группы молча
    ;; откатывалась бы на запасное значение "две опоры" для всех
    ;; пролётов подряд. Ровно та ловушка, ради которой в этом файле и
    ;; заведён приём "прочитать всё - переписать всё же самое"
    ;; (LEP:SetData перезаписывает XDATA ЦЕЛИКОМ).
    (setq Reserve    (LEP:GetDataValue Ent "RESERVE"))
    (setq Pole1      (LEP:GetDataValue Ent "POLE1HANDLE"))
    (setq Pole2      (LEP:GetDataValue Ent "POLE2HANDLE"))
    (setq Method     (LEP:GetDataValue Ent "METHOD"))

    (LEP:SetData Ent
        (append
            (list
                (cons "TYPE" "SPAN")
                (cons "ROUTE" RouteID)
                (cons "STATUS" Status)
                (cons "WIRE" Wire)
                (cons "SECTION" Section)
                (cons "LENGTH" Length)
                (cons "RAWLENGTH" RawLength)
                (cons "POLE1HANDLE" Pole1)
                (cons "POLE2HANDLE" Pole2)
                (cons "LABELHANDLE" NewLabelHandle)
            )
            (if Reserve (list (cons "RESERVE" Reserve)) nil)
            (if Method (list (cons "METHOD" Method)) nil)
        )
    )
)


;=====================================================================
;
; LEP:ReassignRoute
;
; Сканирует ВСЕ слои опор (Проект.+Сущ.) и пролётов ВЛ/КЛ (Проект.+
; Сущ.) на всём чертеже, находит объекты с XDATA ROUTE=OldRouteID и
; перепривязывает их на NewRouteID (остальные поля каждого объекта
; сохраняются - см. LEP:ReassignPoleRoute/SpanRoute выше).
;
; Вызывать из консоли вручную (не отдельная команда C:... - это редкая
; ремонтная операция, не часть обычного рабочего процесса, не хотим
; захламлять список команд ради неё):
;
;   (LEP:ReassignRoute "LEP_ROUTE_UNKNOWN" "LEP_ROUTE_01")
;
; Фильтр по слою через запятую в группе 8 - тот же приём, что уже
; используется в LEP-REPORT.LSP (ЭТАП 1) для объединения ВЛ+КЛ одним
; ssget.
;
;=====================================================================

(defun LEP:ReassignRoute (OldRouteID NewRouteID / SS i Ent Count)

    (setq Count 0)

    ;; Пролёты - ВЛ+КЛ, Проект.+Сущ., одним ssget.
    (setq SS
        (ssget "_X"
            (list
                '(0 . "LWPOLYLINE")
                (cons 8
                    (strcat
                        *LEP-Layer-Proj-VL* "," *LEP-Layer-Exist-VL* ","
                        *LEP-Layer-Proj-KL* "," *LEP-Layer-Exist-KL*
                    )
                )
            )
        )
    )
    (if SS
        (progn
            (setq i 0)
            (repeat (sslength SS)
                (setq Ent (ssname SS i))
                (if (= (LEP:GetDataValue Ent "ROUTE") OldRouteID)
                    (progn
                        (LEP:ReassignSpanRoute Ent NewRouteID)
                        (setq Count (1+ Count))
                    )
                )
                (setq i (1+ i))
            )
        )
    )

    ;; Опоры - Проект.+Сущ., одним ssget.
    (setq SS
        (ssget "_X"
            (list
                '(0 . "INSERT")
                (cons 8 (strcat *LEP-Layer-Proj-Pole* "," *LEP-Layer-Exist-Pole*))
            )
        )
    )
    (if SS
        (progn
            (setq i 0)
            (repeat (sslength SS)
                (setq Ent (ssname SS i))
                (if (= (LEP:GetDataValue Ent "ROUTE") OldRouteID)
                    (progn
                        (LEP:ReassignPoleRoute Ent NewRouteID)
                        (setq Count (1+ Count))
                    )
                )
                (setq i (1+ i))
            )
        )
    )

    (princ (strcat "\n[LEP] Перепривязано объектов с " OldRouteID " на " NewRouteID ": " (itoa Count)))
    (princ)
)


(princ "\nLEP-DATA v1.0 загружен (данные КТП, объединение подписей пролётов, честный STATUS, массовая перепривязка трассы).")
(princ)