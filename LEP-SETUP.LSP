;=====================================================================
;
;   ПРОЕКТ:
;   LEP
;
;   ФАЙЛ:
;   LEP-SETUP.LSP
;
;   ВЕРСИЯ:
;   1.1  (2026-08-04: DIMTFILL - фон под текстом размерной линии.
;        Найдено аудитом "у всех подписей должен быть background mask
;        и draworder front": у выносок MLEADER фон стоял с 2026-07-15,
;        у размерных линий не стоял вообще - Claude)
;   1.0  (LEP:SetLayerTrueColor - True Color подтверждён живым тестом
;        2026-07-22, применён к 4 слоям (0,4кВ Сущ. ВЛ/опоры, КЛ ГНБ/
;        Траншея) - Claude)
;   0.9  (Проект. КЛ - два слоя вместо одного, ГНБ/Траншея, временные
;        ACI-цвета до подтверждения True Color; слой LEP-GEOPOINTS -
;        Claude, 2026-07-20/22)
;   0.8  (DIMSAH/DIMBLK1/DIMBLK2/DIMLDRBLK - стрелка "Oblique" -
;        Claude, 2026-07-15)
;   0.7  (DIMTIH/DIMTOH/DIMTAD - текст размерной линии пролёта
;        поворачивается вместе с линией и садится над ней - Claude,
;        2026-07-15)
;   0.6  (LEP:CreateMLeaderStyle - настройка стиля "Standard" MLEADER
;        под подписи проекта, миграция с LEADER - Claude, 2026-07-15)
;
;   НАЗНАЧЕНИЕ:
;
;   Подготавливает чертёж к работе.
;
;   Создаёт все необходимые слои проекта, единый текстовый стиль
;   (LEP:CreateTextStyle - наклонный ISOCPEUR, высота 1,3) и настраивает
;   стиль выносок MLEADER (LEP:CreateMLeaderStyle - полка/стрелка/
;   высота текста/подчёркивание под подписи проекта).
;
;   Если слой/стиль уже существует —
;   повторно он не создаётся.
;
;   Цвет проектируемых опор сменён с красного на оранжевый (по просьбе
;   пользователя - совпадал по цвету со служебной линией маршрута).
;
;   После завершения выводится краткий отчёт.
;
;=====================================================================



;=====================================================================
;                       СЛУЖЕБНАЯ ФУНКЦИЯ
;=====================================================================
;
; Создание слоя.
;
; Если слой уже существует —
; функция ничего не делает.
;
;=====================================================================

(defun LEP:CreateLayer (LayerName LayerColor /)

    (if (not (tblsearch "LAYER" LayerName))

        (progn

            (command
                "_.LAYER"

                "_Make"
                LayerName

                "_Color"
                LayerColor
                LayerName

                ""

            )

            (princ
                (strcat
                    "\nСоздан слой: "
                    LayerName
                )
            )

        )

        (princ
            (strcat
                "\nУже существует: "
                LayerName
            )
        )

    )

)



;=====================================================================
;                       СЛУЖЕБНАЯ ФУНКЦИЯ
;=====================================================================
;
; Выключает печать слоя (Plot = No) - НЕЗАВИСИМО от того, создан он
; только что или уже был. Используется для служебного слоя маршрута
; LEP-ROUTE-SERVICE: даже если пользователь забудет спрятать его
; командой LEP-ROUTEVIS перед печатью, на бумаге он всё равно не
; появится.
;
; Правим DXF-запись слоя напрямую через entmod (группа 290 = флаг
; печати, 0 = не печатать) - а не через (command "-layer" "Plot" ...):
; порядок промптов у этой команды в разных версиях AutoCAD отличается
; (то ли сначала спрашивает имя слоя, то ли Yes/No), а мы уже дважды
; ловили баги именно на неправильном порядке аргументов у command
; (LEADER, -linetype). entmod детерминирован и не зависит от версии.
;
;=====================================================================

(defun LEP:SetLayerNoPlot (LayerName / LayerEnt LayerData)
    (setq LayerEnt (tblobjname "LAYER" LayerName))
    (if LayerEnt
        (progn
            (setq LayerData (entget LayerEnt))
            (if (assoc 290 LayerData)
                (setq LayerData (subst (cons 290 0) (assoc 290 LayerData) LayerData))
                (setq LayerData (append LayerData (list (cons 290 0))))
            )
            (entmod LayerData)
        )
    )
)



;=====================================================================
;                       СЛУЖЕБНАЯ ФУНКЦИЯ
;=====================================================================
;
; LEP:SetLayerTrueColor
;
; Задаёт слою НАСТОЯЩИЙ RGB-цвет (True Color), а не обычный номер ACI
; (1-255), которым пользуется весь остальной проект. Через entmod
; DXF-группы 420 у таблицы LAYER (24-битное упакованное значение
; R*65536 + G*256 + B) - ✅ ПОДТВЕРЖДЕНО ЖИВЫМ ТЕСТОМ 2026-07-22
; (пользователь создал тестовый слой этим же кодом, диспетчер слоёв
; AutoCAD показал реальный фиолетовый цвет, не серый/дефолтный) - тот
; же принцип "менять DXF-группу напрямую, не через command", что и у
; LEP:SetLayerNoPlot выше (группа 290) - надёжнее, чем гадать порядок
; аргументов `-LAYER Color Truecolor ...` в командной строке.
;
; Вызывается ПОСЛЕ LEP:CreateLayer (которая создаёт слой с обычным
; ACI-цветом как начальным значением) - True Color просто
; переопределяет его сразу следующей строкой в C:LEP-SETUP.
;=====================================================================

(defun LEP:SetLayerTrueColor (LayerName R G B / LayerEnt LayerData Value)
    (setq LayerEnt (tblobjname "LAYER" LayerName))
    (if LayerEnt
        (progn
            (setq LayerData (entget LayerEnt))
            (setq Value (+ (* R 65536) (* G 256) B))
            (if (assoc 420 LayerData)
                (setq LayerData (subst (cons 420 Value) (assoc 420 LayerData) LayerData))
                (setq LayerData (append LayerData (list (cons 420 Value))))
            )
            (entmod LayerData)
        )
    )
)



;=====================================================================
;                       СЛУЖЕБНАЯ ФУНКЦИЯ
;=====================================================================
;
; LEP:CreateTextStyle
;
; Создаёт (если ещё нет) единый текстовый стиль проекта -
; *LEP-TextStyle-Name* в LEP-CONFIG.LSP (наклонный ISOCPEUR, высота
; 1,3 - по просьбе пользователя 2026-07-10). Через entmake на таблицу
; STYLE - то же самое, что выбрать шрифт мышкой в диалоге "Текстовые
; стили", просто кодом. Создаётся один раз, если уже есть - не
; трогается (тот же принцип, что и у слоёв/блока символа опоры).
;
; Делает стиль ТЕКУЩИМ для обычного текста (TEXTSTYLE) И для
; размерных линий (DIMTXSTY) - у стиля задана явная (не нулевая)
; высота, поэтому для DIMALIGNED она автоматически замещает DIMTXT
; (см. подробное объяснение в LEP-CONFIG.LSP).
;
; ⚠️ ШРИФТ: "ISOCPEUR" (без .shx!) - на проверенной установке AutoCAD
; это TrueType-шрифт (не SHX-файл, хотя выглядит похоже) - живьём
; сверено через диалог "Текстовые стили" (Family, иконка "TT"). Если
; когда-нибудь понадобится вернуться к классическому SHX - на той же
; установке реально существует "isocp.shx" (без "eur").
;
; ⚠️ УГОЛ НАКЛОНА (группа DXF 50 у STYLE) - в РАДИАНАХ, как и почти
; все остальные углы в проекте (ИСПРАВЛЕНО 2026-07-10 - изначально по
; памяти предполагал градусы, оказалось неверно: диалог AutoCAD
; показывает пользователю градусы, но внутри DXF хранит уже в
; радианах - проверено вживую в консоли на маленьком тесте, только
; после перевода в радианы наклон реально появился на экране).
; *LEP-TextStyle-ObliqueAngle* в CONFIG хранится в ГРАДУСАХ (удобнее
; человеку менять) - перевод в радианы происходит здесь же, при
; вставке в entmake.
;
; ИСПРАВЛЕНО РАНЕЕ (2026-07-10): entmake для STYLE был без маркеров
; подкласса (100 . "AcDbSymbolTableRecord")/(100 . "AcDbTextStyleTableRecord") -
; запись формально создавалась (tblsearch её находил), но AutoCAD не
; считал её полноценной, и "(setvar "TEXTSTYLE" ...)" сразу после этого
; падал с "AutoCAD variable setting rejected". Добавлены оба маркера.
;
; ДОПОЛНИТЕЛЬНО: сама функция вызывается ИЗНУТРИ C:LEP-SETUP - если
; setvar всё же не сработает (например шрифт недоступен в конкретной
; установке AutoCAD) - необработанная ошибка тут оборвала бы остаток
; C:LEP-SETUP (слои LEP-DIM/LEP-MANUAL) И следующую за (C:LEP-SETUP)
; строку в LEP-START.LSP - (LEP:CreatePoleSymbolBlock). Поэтому
; setvar-вызовы обёрнуты в vl-catch-all-apply - если не получится
; сделать стиль текущим, будет только предупреждение в консоли, а не
; обрыв всей остальной подготовки чертежа.
;
;=====================================================================

(defun LEP:CreateTextStyle (/ StyleResult ObliqueRad)

    (setq ObliqueRad (/ (* *LEP-TextStyle-ObliqueAngle* pi) 180.0))

    (if (not (tblsearch "STYLE" *LEP-TextStyle-Name*))
        (progn
            (entmake
                (list
                    (cons 0 "STYLE")
                    (cons 100 "AcDbSymbolTableRecord")
                    (cons 100 "AcDbTextStyleTableRecord")
                    (cons 2 *LEP-TextStyle-Name*)
                    (cons 70 0)
                    (cons 40 *LEP-TextHeight*)
                    (cons 41 1.0)
                    (cons 50 ObliqueRad)
                    (cons 71 0)
                    (cons 42 *LEP-TextHeight*)
                    (cons 3 *LEP-TextStyle-Font*)
                    (cons 4 "")
                )
            )
            (princ (strcat "\nСоздан текстовый стиль: " *LEP-TextStyle-Name*))
        )
        (princ (strcat "\nУже существует: " *LEP-TextStyle-Name*))
    )

    ;; Обёрнуто в vl-catch-all-apply - если AutoCAD откажется сделать
    ;; стиль текущим (например, не найдёт шрифт isocpeur.shx в этой
    ;; конкретной установке) - только предупреждение в консоль, а не
    ;; обрыв остатка C:LEP-SETUP/LEP-START.LSP (см. ⚠️ в шапке функции).
    (setq StyleResult
        (vl-catch-all-apply
            '(lambda ()
                (setvar "TEXTSTYLE" *LEP-TextStyle-Name*)
                (setvar "DIMTXSTY" *LEP-TextStyle-Name*)
            )
         '())
    )

    (if (vl-catch-all-error-p StyleResult)
        (princ
            (strcat
                "\n[LEP-SETUP] ВНИМАНИЕ: не удалось сделать текущим текстовый стиль \""
                *LEP-TextStyle-Name*
                "\" (возможно, шрифт " *LEP-TextStyle-Font*
                " недоступен в этой установке AutoCAD) - подписи будут создаваться прежним стилем."
            )
        )
    )
)



;=====================================================================
;                       СЛУЖЕБНАЯ ФУНКЦИЯ
;=====================================================================
;
; LEP:CreateMLeaderStyle
;
; Настраивает стиль "Standard" MLEADERSTYLE под подписи-выноски
; проекта (полка/стрелка/высота текста/цвет/подчёркивание) - миграция
; с классического LEADER, см. ПОДРОБНОЕ обоснование и происхождение
; каждого значения в LEP-CONFIG.LSP, раздел "СТИЛЬ ВЫНОСОК MLEADER".
;
; ⚠️ MLEADERSTYLE - НЕ классическая именная таблица AutoCAD (в отличие
; от LAYER/STYLE, которые ищутся через tblsearch/tblobjname) - это
; объект внутри именованного словаря чертежа. Путь к нему:
; namedobjdict -> словарь "ACAD_MLEADERSTYLE" -> запись "Standard".
; Именно так и НИКАК иначе - tblobjname для "MLEADERSTYLE" вернёт nil
; (уже ловили этот баг живьём: entmod падал с "bad argument type:
; lentityp nil").
;
; Правим ТОЧЕЧНО, через entget/subst/entmod, 10 конкретных DXF-групп
; (42/43/44/45/93/174/178/295/298/342) - все остальные поля записи
; (включая хендлы на другие объекты чертежа, группы 340/341/343)
; остаются как есть, не трогаем и не копируем - см. подробности в
; LEP-CONFIG.LSP, почему это важно.
;
; ГРУППА 342 (TextStyleHandle) - ⚠️ ПОДТВЕРЖДЕНО живым тестом
; 2026-07-15 (и на чистом, и на боевом чертеже): это хендл текстового
; стиля, которым рисуется контент мультивыноски. По умолчанию у
; "Standard" смотрит на стандартный текстовый стиль AutoCAD (без
; наклона), поэтому подписи через MLEADER рисовались БЕЗ наклона 10°/
; шрифта ISOCPEUR, хотя весь остальной текст на чертеже - с ними
; (LEP:CreateTextStyle выше). Значение - хендл НАШЕГО текстового
; стиля (*LEP-TextStyle-Name*, "LEP-STYLE"), получается через
; tblobjname (STYLE - обычная именная таблица, в отличие от самого
; MLEADERSTYLE) - ВАЖНО вызывать LEP:CreateMLeaderStyle СТРОГО ПОСЛЕ
; LEP:CreateTextStyle в C:LEP-SETUP, иначе стиль LEP-STYLE ещё не
; будет существовать и tblobjname вернёт nil.
;
; Как и LEP:SetLayerNoPlot/DIMASZ выше - НЕ создаёт ничего нового
; (стиль "Standard" существует в любом чертеже AutoCAD "из коробки"),
; просто перезаписывает значения при каждой загрузке чертежа. Поэтому
; никакой проверки "уже настроено/ещё нет" не нужно - функция
; идемпотентна сама по себе (повторный вызов просто запишет те же
; числа заново).
;
;=====================================================================

(defun LEP:CreateMLeaderStyle (/ StyleEnt StyleData TextStyleEnt)

    (setq StyleEnt
        (cdr
            (assoc -1
                (dictsearch
                    (cdr (assoc -1 (dictsearch (namedobjdict) "ACAD_MLEADERSTYLE")))
                    "Standard"
                )
            )
        )
    )

    (if StyleEnt
        (progn
            (setq StyleData (entget StyleEnt))

            (setq StyleData (subst (cons 43  *LEP-MLeader-LandingDistance*) (assoc 43  StyleData) StyleData))
            (setq StyleData (subst (cons 42  *LEP-MLeader-LandingGap*)      (assoc 42  StyleData) StyleData))
            (setq StyleData (subst (cons 44  *LEP-MLeader-ArrowSize*)       (assoc 44  StyleData) StyleData))
            (setq StyleData (subst (cons 45  *LEP-TextHeight*)              (assoc 45  StyleData) StyleData))
            (setq StyleData (subst (cons 93  *LEP-MLeader-TextColorValue*)  (assoc 93  StyleData) StyleData))
            (setq StyleData (subst (cons 174 *LEP-MLeader-AttachLeft*)      (assoc 174 StyleData) StyleData))
            (setq StyleData (subst (cons 178 *LEP-MLeader-AttachRight*)     (assoc 178 StyleData) StyleData))
            (setq StyleData (subst (cons 295 *LEP-MLeader-Underline1*)      (assoc 295 StyleData) StyleData))
            (setq StyleData (subst (cons 298 *LEP-MLeader-Underline2*)      (assoc 298 StyleData) StyleData))

            ;; Группа 342 - текстовый стиль контента (см. ⚠️ выше) -
            ;; STYLE это обычная именная таблица, tblobjname тут
            ;; работает (в отличие от самого MLEADERSTYLE).
            (setq TextStyleEnt (tblobjname "STYLE" *LEP-TextStyle-Name*))
            (if TextStyleEnt
                (setq StyleData (subst (cons 342 TextStyleEnt) (assoc 342 StyleData) StyleData))
                (princ (strcat "\n[LEP-SETUP] ВНИМАНИЕ: текстовый стиль \"" *LEP-TextStyle-Name* "\" не найден - выноски MLEADER останутся без наклона/шрифта проекта."))
            )

            (entmod StyleData)

            (princ "\nНастроен стиль выносок MLEADER: Standard")
        )
        (princ "\n[LEP-SETUP] ВНИМАНИЕ: не найден стиль MLEADERSTYLE \"Standard\" - подписи-выноски будут выглядеть по умолчанию AutoCAD.")
    )
)



;=====================================================================
;
;                     ОСНОВНАЯ КОМАНДА
;
;=====================================================================

(defun C:LEP-SETUP (/)

    (princ "\n")
    (princ "========================================")
    (princ "\nПодготовка чертежа LEP")
    (princ "\n========================================")



    ;;------------------------------------------------------------
    ;; Подложка
    ;;------------------------------------------------------------

    (LEP:CreateLayer
        *LEP-Layer-Kadastr*
        *LEP-Color-Kadastr*
    )



    ;;------------------------------------------------------------
    ;; Служебная линия маршрута (не ВЛ/КЛ, только для констрейнтов)
    ;;------------------------------------------------------------

    (LEP:CreateLayer
        *LEP-Layer-Route*
        *LEP-Color-Proj*
    )
    (LEP:SetLayerNoPlot *LEP-Layer-Route*)



    ;;------------------------------------------------------------
    ;; Воздушные линии
    ;;
    ;; ✅ ДОБАВЛЕНО 2026-07-22 (по просьбе пользователя - цвет зависит
    ;; от класса напряжения, не только от статуса): 4 слоя вместо 2.
    ;; 10кВ Проект - оранжевый (без изменений), 0,4кВ Проект - синий,
    ;; 10кВ Сущ - красный, 0,4кВ Сущ - True Color (✅ подтверждён живым
    ;; тестом 2026-07-22, см. LEP:SetLayerTrueColor выше).
    ;;------------------------------------------------------------

    (LEP:CreateLayer
        *LEP-Layer-Proj-VL-10*
        *LEP-Color-Proj-VL*
    )

    (LEP:CreateLayer
        *LEP-Layer-Proj-VL-04*
        *LEP-Color-Proj-VL-04*
    )

    (LEP:CreateLayer
        *LEP-Layer-Exist-VL-10*
        *LEP-Color-Exist-VL-10*
    )

    (LEP:CreateLayer
        *LEP-Layer-Exist-VL-04*
        *LEP-Color-Exist-VL-04-Placeholder*
    )
    ;; ✅ True Color подтверждён живым тестом 2026-07-22 - переопределяем
    ;; ACI-заглушку выше настоящим RGB.
    (LEP:SetLayerTrueColor
        *LEP-Layer-Exist-VL-04*
        (car *LEP-TrueColor-Exist-VL-04*)
        (cadr *LEP-TrueColor-Exist-VL-04*)
        (caddr *LEP-TrueColor-Exist-VL-04*)
    )



    ;;------------------------------------------------------------
    ;; Кабельные линии
    ;;
    ;; ✅ ДОБАВЛЕНО 2026-07-22: Проект. КЛ теперь два слоя вместо одного
    ;; (способ прокладки ГНБ/Траншея, см. LEP-CONFIG.LSP - там же
    ;; объяснение, почему *LEP-Layer-Proj-KL* САМ по себе больше НЕ
    ;; передаётся в LEP:CreateLayer напрямую - это теперь составная
    ;; строка "слой1,слой2" для сканирования, а не имя одного слоя).
    ;; Цвета - True Color (✅ подтверждён живым тестом 2026-07-22, см.
    ;; LEP:SetLayerTrueColor выше).
    ;;------------------------------------------------------------

    (LEP:CreateLayer
        *LEP-Layer-Proj-KL-GNB*
        *LEP-Color-Proj-KL-GNB-Placeholder*
    )
    (LEP:SetLayerTrueColor
        *LEP-Layer-Proj-KL-GNB*
        (car *LEP-TrueColor-Proj-KL-GNB*)
        (cadr *LEP-TrueColor-Proj-KL-GNB*)
        (caddr *LEP-TrueColor-Proj-KL-GNB*)
    )

    (LEP:CreateLayer
        *LEP-Layer-Proj-KL-Trench*
        *LEP-Color-Proj-KL-Trench-Placeholder*
    )
    (LEP:SetLayerTrueColor
        *LEP-Layer-Proj-KL-Trench*
        (car *LEP-TrueColor-Proj-KL-Trench*)
        (cadr *LEP-TrueColor-Proj-KL-Trench*)
        (caddr *LEP-TrueColor-Proj-KL-Trench*)
    )

    (LEP:CreateLayer
        *LEP-Layer-Exist-KL*
        *LEP-Color-Exist*
    )



    ;;------------------------------------------------------------
    ;; Опоры
    ;;------------------------------------------------------------

    ;; Цвет проектируемых опор 10кВ - ОРАНЖЕВЫЙ (*LEP-Color-Proj-VL*), не
    ;; красный (*LEP-Color-Proj*) - по просьбе пользователя 2026-07-10,
    ;; т.к. красный совпадал по цвету со служебной линией маршрута и
    ;; визуально путался с ней.
    ;;
    ;; ✅ ДОБАВЛЕНО 2026-07-22: та же логика "класс x статус", что и у
    ;; ВЛ выше - 4 слоя вместо 2 (см. подробности в LEP-CONFIG.LSP).
    (LEP:CreateLayer
        *LEP-Layer-Proj-Pole-10*
        *LEP-Color-Proj-VL*
    )

    (LEP:CreateLayer
        *LEP-Layer-Proj-Pole-04*
        *LEP-Color-Proj-VL-04*
    )

    (LEP:CreateLayer
        *LEP-Layer-Exist-Pole-10*
        *LEP-Color-Exist-VL-10*
    )

    (LEP:CreateLayer
        *LEP-Layer-Exist-Pole-04*
        *LEP-Color-Exist-VL-04-Placeholder*
    )
    (LEP:SetLayerTrueColor
        *LEP-Layer-Exist-Pole-04*
        (car *LEP-TrueColor-Exist-VL-04*)
        (cadr *LEP-TrueColor-Exist-VL-04*)
        (caddr *LEP-TrueColor-Exist-VL-04*)
    )



    ;;------------------------------------------------------------
    ;; Подстанции
    ;;------------------------------------------------------------

    (LEP:CreateLayer
        *LEP-Layer-Proj-MTP*
        *LEP-Color-Proj*
    )

    (LEP:CreateLayer
        *LEP-Layer-Proj-RLK*
        *LEP-Color-Proj*
    )

    (LEP:CreateLayer
        *LEP-Layer-Proj-TP*
        *LEP-Color-Proj*
    )

    (LEP:CreateLayer
        *LEP-Layer-Exist-TP*
        *LEP-Color-Exist*
    )



    ;;------------------------------------------------------------
    ;; Текст
    ;;------------------------------------------------------------

    (LEP:CreateLayer
        *LEP-Layer-Text*
        *LEP-Color-Text*
    )

    ;; Единый текстовый стиль проекта (наклонный ISOCPEUR, высота 1,3) -
    ;; см. LEP:CreateTextStyle выше и пояснение в LEP-CONFIG.LSP.
    (LEP:CreateTextStyle)

    ;; Размер стрелки = длина полки выносок (DIMASZ) - это и есть
    ;; лечение "отступа перед текстом" у подписей, см. подробный
    ;; комментарий у *LEP-Dim-ArrowSize* в LEP-CONFIG.LSP (найдено и
    ;; подтверждено живым тестом 2026-07-11). Заодно мельчают стрелки
    ;; размерных линий пролётов - сознательно.
    (setvar "DIMASZ" *LEP-Dim-ArrowSize*)

    ;; Текст размерной линии пролёта поворачивается вместе с линией и
    ;; садится НАД ней (не разрывает её) - см. подробное обоснование в
    ;; LEP-CONFIG.LSP, раздел "ОРИЕНТАЦИЯ ТЕКСТА РАЗМЕРНОЙ ЛИНИИ
    ;; ПРОЛЁТА". Раньше эти переменные не трогались вообще - дефолт
    ;; AutoCAD (DIMTIH/DIMTOH=1) держал текст всегда горизонтальным.
    (setvar "DIMTIH" *LEP-Dim-TextInsideHorizontal*)
    (setvar "DIMTOH" *LEP-Dim-TextOutsideHorizontal*)
    (setvar "DIMTAD" *LEP-Dim-TextAbove*)

    ;; ✅ ДОБАВЛЕНО 2026-08-04: фон под текстом размера (DIMTFILL).
    ;; У выносок MLEADER фон стоит с 2026-07-15, а у размерных линий
    ;; не стоял вообще - держался дефолт AutoCAD "без фона", и поверх
    ;; подосновы число размера читалось плохо. Разбор - в
    ;; LEP-CONFIG.LSP, там же рядом с DIMTAD.
    (setvar "DIMTFILL" *LEP-Dim-TextFill*)

    ;; Форма стрелки - "Oblique" (косая черта) вместо дефолтной
    ;; закрашенной стрелки, для First/Second/Leader сразу (диалог
    ;; "Symbols and Arrows") - см. *LEP-Dim-ArrowBlock* в LEP-CONFIG.LSP.
    ;; DIMSAH=1 нужен, чтобы DIMBLK1/DIMBLK2 вообще учитывались (иначе
    ;; работал бы только общий DIMBLK).
    (setvar "DIMSAH" 1)
    (setvar "DIMBLK1" *LEP-Dim-ArrowBlock*)
    (setvar "DIMBLK2" *LEP-Dim-ArrowBlock*)
    (setvar "DIMLDRBLK" *LEP-Dim-ArrowBlock*)

    ;; Стиль выносок MLEADER (полка/стрелка/высота текста/подчёркивание) -
    ;; миграция подписей с LEADER на MLEADER, см. LEP:CreateMLeaderStyle
    ;; выше и подробное обоснование в LEP-CONFIG.LSP.
    (LEP:CreateMLeaderStyle)



    ;;------------------------------------------------------------
    ;; Размеры
    ;;------------------------------------------------------------

    (LEP:CreateLayer
        *LEP-Layer-Dim*
        *LEP-Color-Dim*
    )



    ;;------------------------------------------------------------
    ;; GPS-точки (временные зелёные кружки-ориентиры, LEP-GEOPOINTS.LSP)
    ;;
    ;; Непечатаемый служебный слой - тот же принцип, что и у
    ;; *LEP-Layer-Route* (LEP:SetLayerNoPlot ниже): это рабочий
    ;; ориентир для расстановки опор, а не часть готового чертежа,
    ;; не должен случайно попасть в PDF, даже если пользователь забудет
    ;; его выключить/очистить перед печатью.
    ;;------------------------------------------------------------

    (LEP:CreateLayer
        *LEP-Layer-GeoPoints*
        *LEP-Color-GeoPoints*
    )
    (LEP:SetLayerNoPlot *LEP-Layer-GeoPoints*)



    ;;------------------------------------------------------------
    ;; Точки смены способа прокладки (маркеры-кружки,
    ;; LEP-TRANSSYM.LSP) - 2026-07-24
    ;;
    ;; Тоже НЕПЕЧАТАЕМЫЙ служебный слой, по прямому требованию
    ;; пользователя ("кружок не выводится на печать или PDF") - и по
    ;; той же логике, что у двух слоёв выше: маркер нужен только для
    ;; черчения (за него цепляются концы двух пролётов с разным
    ;; способом прокладки), а на готовом плане переход и так виден -
    ;; участки ГНБ и траншеи лежат на разных слоях с разными цветами.
    ;;------------------------------------------------------------

    (LEP:CreateLayer
        *LEP-Layer-Transition*
        *LEP-Color-Transition*
    )
    (LEP:SetLayerNoPlot *LEP-Layer-Transition*)



    ;;------------------------------------------------------------
    ;; Ручное черчение (создаётся последним - см. ниже)
    ;;
    ;; "-LAYER Make" делает только что созданный слой ТЕКУЩИМ - это
    ;; свойство самой команды AutoCAD, никак не обойти. Раз после
    ;; LEP-SETUP слой всё равно "уедет", пусть уезжает сюда - на
    ;; безопасный черновой слой, а не на случайный технический
    ;; (раньше им оказывался LEP-DIM просто потому, что создавался
    ;; последним по списку). LEP-SETUP запускается автоматически при
    ;; каждой загрузке LEP-START.LSP (см. этот файл), поэтому после
    ;; каждой загрузки чертежа текущим слоем будет именно этот.
    ;;------------------------------------------------------------

    (LEP:CreateLayer
        *LEP-Layer-Manual*
        *LEP-Color-Manual*
    )

    ;;------------------------------------------------------------
    ;; ⚠️ ФИКС 2026-07-24 (баг найден пользователем на живом чертеже).
    ;;
    ;; Приём "создаём LEP-MANUAL последним, и он сам станет текущим"
    ;; работал только на ПУСТОМ чертеже. LEP:CreateLayer запускает
    ;; "-LAYER Make" ТОЛЬКО если слоя ещё нет (см. её код выше в этом
    ;; файле) - а на чертеже, где вы уже работали, все слои существуют,
    ;; и создаваться будет РОВНО ОДИН: новый, только что добавленный в
    ;; программу. Текущим станет ОН.
    ;;
    ;; Ровно это и случилось: после добавления слоя LEP-TRANSITION
    ;; (маркеры смены способа прокладки, непечатаемый) текущим слоем на
    ;; уже начатом чертеже стал он - и подпись кабельного киоска,
    ;; которая рисуется командой "_.MLEADER" на текущем слое, легла на
    ;; непечатаемый слой. В PDF она бы просто не попала.
    ;;
    ;; Поэтому текущий слой теперь выставляется ЯВНО, последней
    ;; строкой, а не как побочный эффект порядка создания. Порядок
    ;; создания при этом оставлен прежним - он больше ни на что не
    ;; влияет, но и вреда не приносит, а менять его без нужды незачем.
    ;;
    ;; ⚠️ Вторая половина того же фикса - в LEP:CreateKtpLabel/
    ;; LEP:CreateKkLabel (LEP-END.LSP): они, в отличие от подписей опор
    ;; и пролётов, вообще не переключали слой перед "_.MLEADER".
    ;; Настоящая причина бага именно там; здесь - защита от того, чтобы
    ;; СЛЕДУЮЩИЙ новый слой не устроил такой же сюрприз в другом месте.
    ;;------------------------------------------------------------

    (LEP:SetCurrentLayer *LEP-Layer-Manual*)



    (princ)

    (princ "\n")
    (princ "========================================")
    (princ "\nПодготовка завершена.")
    (princ "\n========================================")

    (princ)

)