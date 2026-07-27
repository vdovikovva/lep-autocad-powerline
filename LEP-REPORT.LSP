;=====================================================================
; ПРОЕКТ:       LEP (Автоматизация проектирования ЛЭП)
; ФАЙЛ:         LEP-REPORT.LSP
; ВЕРСИЯ:       1.8  (ЭТАП 1.7 - труба для ГНБ-прокола отдельной
;               позицией: пролёты ГНБ группируются в проколы по общей
;               подписи (LABELHANDLE), на каждый прокол считается
;               (вверх(длина/13) + 1) x 2 труб, LEP:AddToBoreList -
;               Claude, 2026-07-24)
;               1.7  (ЭТАП 2.6 - наземные КТП, отдельный скан слоя
;               *LEP-Layer-Proj-TP*, название строки включает номер
;               КТП, Claude, 2026-07-22)
;               1.6  (LEP:GetEquipLabel - комментарий про обратную
;               совместимость МТП по мощности, Claude, 2026-07-16)
;               1.5  (убрано ложное предупреждение "чертёж не в папке
;               модулей" - правило DWG-рядом-с-модулями снято, Claude,
;               2026-07-16)
;               1.4  (ЭТАП 2.5 - оборудование на существующих опорах,
;               LEP:GetEquipLabel вынесена отдельно, Claude, 2026-07-15)
;               1.3  (метраж целым числом, локале-независимо -
;               аудит Claude Fable, 2026-07-11)
;
; ПРАВКИ В ЭТОЙ ВЕРСИИ:
;
; -1. МТП/РЛК/ЩУ/ПУ (LEP-END.LSP) теперь тоже считаются - ключ EQUIP
;    в XDATA опоры (LEP:AddEquipData) добавляет отдельную строку в
;    ведомость сверх обычного подсчёта опоры по типу. Заодно
;    LEP:WriteMasterListBlock перестал слепо клеить "Опора " ко всем
;    строкам с Unit="шт." - теперь только к тем, что реально есть в
;    *LEP-PoleTypes* (иначе "РЛК" превращалось бы в "Опора РЛК").
;
;
; 0. ПОРЯДОК ТРАСС: раньше в CSV трассы шли не в том порядке, в каком
;    создавались (ssget "_X" отдаёт объекты, похоже, в порядке
;    внутренней базы чертежа, а не создания - на практике получался
;    обратный порядок, 3-2-1 вместо 1-2-3). Список трасс теперь
;    сортируется по RouteID перед записью (vl-sort) - формат ID с
;    ведущим нулём ("LEP_ROUTE_01") сортируется как строка ровно в
;    нужном числовом порядке.
;
; 1. ПУТЬ К CSV: если чертёж ещё ни разу не сохранён в папку с
;    модулями LEP (например, только что создан и лежит в Documents
;    по умолчанию), CSV попадал именно туда, а не в папку проекта -
;    потому что путь берётся из (getvar "DWGPREFIX"), а это "папка,
;    где СЕЙЧАС сохранён чертёж", в точности как и для TRUSTEDPATHS в
;    LEP-START.LSP. Как только чертёж сохранён в нужную папку - всё
;    само становится правильно, это не баг, а следствие правила
;    проекта "DWG должен лежать рядом с модулями" (см. CLAUDE.md).
;    Автоматически сохранять чертёж НЕ стали - опасно (может тормозить
;    на больших файлах/медленных дисках, а на "черновом" чертеже,
;    который пользователь ещё не готов сохранять, незапрошенное
;    сохранение может быть и вовсе нежелательным). Вместо этого -
;    просто явное предупреждение перед записью, если папка чертежа не
;    совпадает с папкой модулей.
;
;    ⚠️ СНЯТО 2026-07-16: правило "DWG рядом с модулями" отменено (см.
;    CLAUDE.md) - модули теперь ищутся через Support File Search Path,
;    а не через папку чертежа. Предупреждение выше стало бы ложной
;    тревогой на каждой обычной выгрузке (DWG теперь В НОРМЕ лежит НЕ
;    в папке модулей) - убрано полностью (было "ЭТАП 3", см. ниже по
;    файлу). CSV, как и раньше, пишется рядом с самим чертежом
;    (DWGPREFIX) - это никогда не зависело от папки модулей, только
;    предупреждение про несовпадение папок было лишним и снято.
;
; 2. СТРУКТУРА CSV: раньше название трассы ("LEP_ROUTE_0001" или
;    "ИТОГО") повторялось в каждой строке - бессмысленно и неудобно
;    читать. Теперь название - отдельная строка-заголовок над своим
;    блоком материалов, дальше в блоке только сами материалы.
;
; 3. КОДИРОВКА - НАЙДЕНО ПРАВИЛЬНОЕ РЕШЕНИЕ (после 3 неудачных попыток
;    городить самодельное кодирование через write-char - все отменены):
;    У функции (open ...) в AutoLISP (начиная с AutoCAD 2021) есть
;    ТРЕТИЙ необязательный аргумент - кодировка файла:
;      (open "путь" "w" "utf8")
;    Без него open по умолчанию использует старую однобайтовую
;    кодировку (Windows-1251 для кириллицы на этой системе) - именно
;    поэтому все предыдущие попытки (включая ручную сборку байт UTF-8
;    через write-char) не работали: сам write-char ни при чём, дело
;    было в РЕЖИМЕ ОТКРЫТИЯ ФАЙЛА. Проверено вживую в консоли AutoCAD:
;    после (open ... "w" "utf8") байты (ascii "К") записываются как
;    ровно D0 9A - правильный UTF-8 для U+041A. Системная переменная
;    LISPSYS (которая теоретически тоже влияет на это в документации)
;    на этом Mac вообще не существует (getvar возвращает nil) - но
;    аргумент "utf8" у open работает и без неё.
;    Источник: https://help.autodesk.com/cloudhelp/2024/ENU/AutoCAD-AutoLISP-Reference/files/GUID-089A323F-21FF-4337-99A9-375758E23BA4.htm
;
;    ДОБАВЛЕНО (v1.0): "utf8" без BOM отлично открывался в Sublime/
;    Notes/Quick Look, но НЕ в Excel на Mac - Excel при открытии
;    двойным кликом без BOM угадывает кодировку сам и промахивается
;    (берёт Mac Roman вместо UTF-8) - это известная особенность
;    именно Excel, не файла. Заменено на "utf8-bom" (тоже официально
;    документированный вариант) - добавляет метку UTF-8 (3 байта
;    EF BB BF) в начало файла, по которой Excel уже определяет
;    кодировку верно. Остальным программам, которые и так открывали
;    правильно, эта метка не мешает (невидима/игнорируется).
;    Проверено вживую: байты файла = EF BB BF D0 9A (BOM + "К").
;
; НАЗНАЧЕНИЕ: Сбор объёмов материалов и опор (без округления) с
; разделением по трассам и экспортом в CSV.
;=====================================================================


;=====================================================================
; LEP:AddToMasterList
;
; Добавляет значение (Value) под именем материала (ItemName) в общий
; список MasterList, сгруппированный по трассам (RouteID). Если такая
; трасса/материал уже встречались - значение прибавляется к тому, что
; уже накоплено (счётчик опор или метраж провода/кабеля - смотря что
; передали).
;
; Структура MasterList:
; (
;   (RouteID . ( (ItemName . (Value . Unit)) (ItemName . (Value . Unit)) ... ))
;   ...
; )
;
; Unit - строка единицы измерения ("шт." для опор, "м." для провода/
; кабеля) - хранится вместе со значением, чтобы при выводе в CSV не
; гадать, как форматировать число (штуки - целым, метры - с двумя
; знаками после запятой).
;
; Возвращает: обновлённый MasterList.
;=====================================================================

(defun LEP:AddToMasterList (MasterList RouteID ItemName Value Unit / FoundRoute ItemList FoundItem OldValue)

    (setq FoundRoute (assoc RouteID MasterList))

    (if FoundRoute
        (progn
            (setq ItemList (cdr FoundRoute))
            (setq FoundItem (assoc ItemName ItemList))
            (if FoundItem
                (progn
                    (setq OldValue (car (cdr FoundItem)))
                    (setq ItemList (subst (cons ItemName (cons (+ OldValue Value) Unit)) FoundItem ItemList))
                )
                (setq ItemList (append ItemList (list (cons ItemName (cons Value Unit)))))
            )
            (setq MasterList (subst (cons RouteID ItemList) FoundRoute MasterList))
        )
        (setq MasterList (append MasterList (list (cons RouteID (list (cons ItemName (cons Value Unit)))))))
    )

    MasterList
)


;=====================================================================
; LEP:AddToBoreList
;
; ✅ ДОБАВЛЕНО 2026-07-24 (позиция "труба для ГНБ-прокола").
;
; Вспомогательный накопитель ОТДЕЛЬНО от MasterList - здесь копятся не
; готовые материалы, а ПРОКОЛЫ: сколько всего метров ГНБ в каждом
; проколе. Считать трубы сразу, пролёт за пролётом, НЕЛЬЗЯ - формула
; добавляет одну запасную трубу НА ПРОКОЛ, а прокол может состоять из
; нескольких пролётов подряд (решение пользователя 2026-07-24). Сначала
; надо собрать всю длину прокола целиком, и только потом делить на 13 и
; добавлять запасную трубу - иначе запасных труб окажется столько же,
; сколько пролётов.
;
; Структура BoreList:
; (
;   (Key . (RouteID . СуммарнаяДлина))
;   ...
; )
;
; Key - признак "это один и тот же прокол", см. ЭТАП 1.7 ниже.
;
; Возвращает: обновлённый BoreList.
;=====================================================================

(defun LEP:AddToBoreList (BoreList Key RouteID RawLen / Found OldLen)

    (setq Found (assoc Key BoreList))

    (if Found
        (progn
            (setq OldLen (cdr (cdr Found)))
            (setq BoreList
                (subst
                    (cons Key (cons (car (cdr Found)) (+ OldLen RawLen)))
                    Found
                    BoreList
                )
            )
        )
        (setq BoreList (append BoreList (list (cons Key (cons RouteID RawLen)))))
    )

    BoreList
)


;=====================================================================
; LEP:MergeMasterList
;
; Сводит данные всех трасс из MasterList в ОДИН общий список
; (ItemName . (Value . Unit)) - без разбивки по трассам. Это и есть
; блок "ИТОГО" для закупки.
;=====================================================================

(defun LEP:MergeMasterList (MasterList / Merged RouteItem ItemList Item FoundItem OldValue)

    (setq Merged nil)

    (foreach RouteItem MasterList
        (setq ItemList (cdr RouteItem))
        (foreach Item ItemList
            (setq FoundItem (assoc (car Item) Merged))
            (if FoundItem
                (progn
                    (setq OldValue (car (cdr FoundItem)))
                    (setq Merged (subst (cons (car Item) (cons (+ OldValue (car (cdr Item))) (cdr (cdr Item)))) FoundItem Merged))
                )
                (setq Merged (append Merged (list Item)))
            )
        )
    )

    Merged
)


;=====================================================================
; LEP:WriteMasterListBlock
;
; Пишет в CSV-файл (File) заголовок блока (Title - реальный ID трассы
; или "ИТОГО" для сводного блока), а под ним - сами материалы этой
; трассы, БЕЗ повтора названия трассы в каждой строке (раньше было
; так, неудобно читать).
;
; Для опор (Unit = "шт." И название есть в *LEP-PoleTypes* - см. ниже)
; название дополняется префиксом "Опора " - для провода/кабеля и для
; оконечного оборудования (РЛК/МТП/ЩУ/ПУ, тоже штучное, но не "опора"
; сама по себе, а то, что на ней висит - LEP-END.LSP) префикс не нужен,
; название и так самодостаточное.
;
; Проверка ИМЕННО по *LEP-PoleTypes* (а не просто "Unit = шт."), т.к.
; после появления LEP-END оборудование тоже считается штуками - если
; судить только по Unit, "Опора " приклеилась бы и к строке "РЛК", что
; бессмысленно (РЛК - не опора, а разъединитель НА опоре).
;=====================================================================

(defun LEP:WriteMasterListBlock (File Title ItemList / Item Name Value Unit ValueStr Prefix)

    (write-line (strcat "=== " Title " ===") File)

    (foreach Item ItemList
        (setq Name (car Item))
        (setq Value (car (cdr Item)))
        (setq Unit (cdr (cdr Item)))

        (if (= Unit "шт.")
            (progn
                (if (assoc Name *LEP-PoleTypes*)
                    (setq Prefix "Опора ")
                    (setq Prefix "")
                )
                (setq ValueStr (itoa (fix Value)))
            )
            (progn
                (setq Prefix "")
                ;; Метраж - тоже ЦЕЛЫМ числом (⚠️ ФИКС 2026-07-11,
                ;; аудит): длины пролётов и так всегда целые (LEP-SPAN
                ;; округляет вверх до метра ещё при создании), а
                ;; прежний вывод "45.00" через rtos с точкой-разделителем
                ;; мог конфликтовать с русской локалью Excel (там
                ;; десятичный разделитель - запятая; "45.00" рисковал
                ;; превратиться в текст/дату). Целое число читается
                ;; одинаково в любой локали. LEP:RoundNearest - на
                ;; случай микроскопической накопленной погрешности
                ;; суммирования, чтобы 45.0000001 не обрезался fix'ом
                ;; куда не надо.
                (setq ValueStr (itoa (LEP:RoundNearest Value)))
            )
        )

        (write-line (strcat Prefix Name ";" ValueStr ";" Unit) File)
    )
)


;=====================================================================
; C:LEP-REPORT - основная команда
;=====================================================================

;=====================================================================
; LEP:GetEquipLabel
;
; Название оборудования по коду EQUIP из XDATA (РЛК/МТП/ЩУ/ПУ, из
; LEP-CONFIG.LSP) - вынесено в отдельную функцию 2026-07-15, чтобы
; не дублировать один и тот же cond в двух местах сканирования
; (обычные опоры + ПУ на существующей опоре, см. ЭТАП 2 и ЭТАП 2.5
; ниже в C:LEP-REPORT).
;
; ⚠️ МТП 2026-07-16: ветка ((= EquipCode "MTP") *LEP-Label-MTP*) -
; ТОЛЬКО обратная совместимость со СТАРЫМИ МТП (поставлены до выбора
; мощности - LEP-END.LSP писал в XDATA просто общий код "MTP", без
; указания мощности). НОВЫЕ МТП пишут в EQUIP сразу ГОТОВУЮ строку
; ("МТП-160/10/0,4" или "МТП-250/10/0,4", *LEP-MTP-Types* в
; LEP-CONFIG.LSP) - для них отдельная ветка не нужна, срабатывает
; запасная (t EquipCode) ниже: код УЖЕ И ЕСТЬ готовое название.
;=====================================================================

(defun LEP:GetEquipLabel (EquipCode)
    (cond
        ((= EquipCode "RLK") *LEP-Label-RLK*)
        ((= EquipCode "MTP") *LEP-Label-MTP*)
        ((= EquipCode "SCHU") *LEP-Label-SchU*)
        ((= EquipCode "PU") *LEP-Label-PU*)
        (t EquipCode)
    )
)


(defun C:LEP-REPORT ( / VL-SS PoleSS ExistPoleSS KtpSS GnbSS i Ent RouteID Status WireName WireLength
                        PoleName EquipCode EquipName EquipStatus KtpName MasterList MergedList CsvPath CsvFile FileCheck
                        RouteItem BoreList BoreItem BoreKey BoreLen RawStr PipeCount)

    (LEP:PrintHeader "Выгрузка ведомости в CSV (только Проект.)")

    (setq MasterList nil)

    ;=================================================================
    ; ЭТАП 1: ПРОЕКТИРУЕМЫЕ ПРОЛЁТЫ (ВЛ и КЛ) - метраж по маркам
    ;=================================================================

    (setq VL-SS (ssget "_X" (list '(0 . "LWPOLYLINE")
                                  (cons 8 (strcat *LEP-Layer-Proj-VL* "," *LEP-Layer-Proj-KL*)))))

    (if VL-SS
        (progn
            (setq i 0)
            (repeat (sslength VL-SS)
                (setq Ent (ssname VL-SS i))
                (setq Status (LEP:GetDataValue Ent "STATUS"))

                (if (= Status "PROJECT")
                    (progn
                        (setq RouteID (LEP:GetDataValue Ent "ROUTE"))
                        (if (not RouteID) (setq RouteID "БЕЗ_ТРАССЫ"))

                        (setq WireName (LEP:GetDataValue Ent "WIRE"))
                        (if (not WireName) (setq WireName "МАРКА_НЕ_УКАЗАНА"))

                        ;; Длина уже посчитана геометрически один раз при
                        ;; создании пролёта в LEP-SPAN - берём готовое
                        ;; значение из XDATA, а не пересчитываем заново.
                        ;; (atof nil) упал бы с ошибкой и остановил всю
                        ;; команду - на случай отсутствия данных у
                        ;; конкретного объекта просто считаем длину 0,
                        ;; а не роняем всю ведомость из-за одного пролёта.
                        (setq WireLength (LEP:GetDataValue Ent "LENGTH"))
                        (if WireLength
                            (setq WireLength (atof WireLength))
                            (setq WireLength 0.0)
                        )

                        (setq MasterList (LEP:AddToMasterList MasterList RouteID WireName WireLength "м."))
                    )
                )
                (setq i (1+ i))
            )
        )
    )

    ;=================================================================
    ; ЭТАП 1.7: ТРУБА ДЛЯ ГНБ-ПРОКОЛА (2026-07-24)
    ;=================================================================
    ;
    ; Отдельная позиция ведомости, НЕ связанная с метражом кабеля:
    ; кабель ГНБ тянут внутри пластиковых труб, которые закупают
    ; отрезками по 13 м (*LEP-GNB-PipeLength*). Формула и её разбор -
    ; в LEP-CONFIG.LSP, раздел "ТРУБА ДЛЯ ГНБ-ПРОКОЛА".
    ;
    ; Считается ТОЛЬКО для проектируемой КЛ, проложенной ГНБ - именно
    ; поэтому здесь свой отдельный ssget по слою
    ; *LEP-Layer-Proj-KL-GNB*, а не общий скан ЭТАПА 1 выше: слой
    ; проектируемой ГНБ-КЛ отдельный (появился 2026-07-22 вместе с
    ; выбором способа прокладки), так что сам факт нахождения объекта
    ; на этом слое уже и есть признак "это ГНБ и это проект".
    ;
    ; ⚠️ ЧТО СЧИТАЕТСЯ ОДНИМ ПРОКОЛОМ. Запасная труба (+1) добавляется
    ; ОДИН РАЗ НА ПРОКОЛ, а не на каждый пролёт - значит программе надо
    ; понять, какие пролёты образуют один сплошной прокол. Признак -
    ; ОБЩАЯ ПОДПИСЬ (LABELHANDLE в XDATA): подписи соседних однородных
    ; пролётов мы и так объединяем в одну (LEP:FinalizeSpanLabel,
    ; LEP-SPAN.LSP), и объединяются они ровно по тому же признаку, что
    ; нужен здесь - идут подряд, та же марка, тот же статус, та же
    ; трасса. То есть "один прокол" = "одна общая подпись". Ничего
    ; нового спрашивать у пользователя не нужно, готовая группировка уже
    ; есть в чертеже.
    ;
    ; Если у пролёта LABELHANDLE почему-то нет (пролёт от старой версии
    ; программы, или подпись стёрли руками и не запускали
    ; LEP-SPAN-REPAIR) - ключом становится СОБСТВЕННЫЙ хендл пролёта.
    ; Тогда он образует прокол сам по себе, и запасная труба посчитается
    ; ему отдельно. Это осознанный запасной вариант: лучше немного
    ; завысить число труб, чем потерять прокол из ведомости совсем.
    ;
    ; Длина берётся СЫРАЯ (RAWLENGTH - геометрия по плану), а не LENGTH:
    ; в LENGTH уже сидят +6 м на подъём кабеля на опору и процент
    ; запаса на укладку кабеля - к длине самой трубы это отношения не
    ; имеет, трубу кладут по факту трассы прокола. Если RAWLENGTH нет
    ; (старый пролёт) - откатываемся на LENGTH, чтобы не получить ноль
    ; труб на реальном проколе.
    ;=================================================================

    (setq GnbSS (ssget "_X" (list '(0 . "LWPOLYLINE")
                                  (cons 8 *LEP-Layer-Proj-KL-GNB*))))

    (setq BoreList nil)

    (if GnbSS
        (progn
            (setq i 0)
            (repeat (sslength GnbSS)
                (setq Ent (ssname GnbSS i))
                (setq Status (LEP:GetDataValue Ent "STATUS"))

                (if (= Status "PROJECT")
                    (progn
                        (setq RouteID (LEP:GetDataValue Ent "ROUTE"))
                        (if (not RouteID) (setq RouteID "БЕЗ_ТРАССЫ"))

                        ;; Ключ прокола - общая подпись, иначе сам пролёт
                        ;; (см. ⚠️ выше).
                        (setq BoreKey (LEP:GetDataValue Ent "LABELHANDLE"))
                        (if (not BoreKey)
                            (setq BoreKey (cdr (assoc 5 (entget Ent))))
                        )

                        ;; Сырая длина по плану, с откатом на LENGTH.
                        (setq RawStr (LEP:GetDataValue Ent "RAWLENGTH"))
                        (if (not RawStr) (setq RawStr (LEP:GetDataValue Ent "LENGTH")))
                        (if RawStr
                            (setq BoreLen (atof RawStr))
                            (setq BoreLen 0.0)
                        )

                        (setq BoreList (LEP:AddToBoreList BoreList BoreKey RouteID BoreLen))
                    )
                )
                (setq i (1+ i))
            )
        )
    )

    ;; Теперь, когда длина каждого прокола собрана целиком, считаем
    ;; трубы. Округление длины прокола на число отрезков - ВВЕРХ
    ;; (LEP:RoundUp): труба продаётся целыми отрезками, "полтрубы"
    ;; купить нельзя. Дальше + запасная труба на прокол и умножение на
    ;; число труб в проколе.
    (foreach BoreItem BoreList
        (setq BoreLen (cdr (cdr BoreItem)))
        (if (> BoreLen 0.0)
            (progn
                (setq PipeCount
                    (* (+ (LEP:RoundUp (/ BoreLen *LEP-GNB-PipeLength*))
                          *LEP-GNB-PipeSpare*
                       )
                       *LEP-GNB-PipesPerBore*
                    )
                )
                (setq MasterList
                    (LEP:AddToMasterList
                        MasterList
                        (car (cdr BoreItem))
                        *LEP-Label-GNB-Pipe*
                        PipeCount
                        "шт."
                    )
                )
            )
        )
    )

    ;=================================================================
    ; ЭТАП 2: ПРОЕКТИРУЕМЫЕ ОПОРЫ - количество по типам
    ;
    ; Заодно считаем оконечное оборудование (РЛК/МТП/ЩУ/ПУ, LEP-END.LSP)
    ; - оно физически "висит" на обычной опоре (ключ EQUIP в XDATA, см.
    ; LEP:AddEquipData), поэтому сама опора и так уже посчитана выше по
    ; MODEL как обычно, а EQUIP добавляет ОТДЕЛЬНУЮ строку в ведомость
    ; для самого оборудования (иначе РЛК/МТП/ЩУ/ПУ вообще не попали бы
    ; в CSV - опора без EQUIP ничем не отличается от обычной опоры).
    ;=================================================================

    (setq PoleSS (ssget "_X" (list '(0 . "INSERT") (cons 8 *LEP-Layer-Proj-Pole*))))

    (if PoleSS
        (progn
            (setq i 0)
            (repeat (sslength PoleSS)
                (setq Ent (ssname PoleSS i))
                (setq Status (LEP:GetDataValue Ent "STATUS"))

                (if (= Status "PROJECT")
                    (progn
                        (setq RouteID (LEP:GetDataValue Ent "ROUTE"))
                        (if (not RouteID) (setq RouteID "БЕЗ_ТРАССЫ"))

                        (setq PoleName (LEP:GetDataValue Ent "MODEL"))
                        (if (not PoleName) (setq PoleName "ТИП_НЕ_УКАЗАН"))

                        (setq MasterList (LEP:AddToMasterList MasterList RouteID PoleName 1 "шт."))

                        (setq EquipCode (LEP:GetDataValue Ent "EQUIP"))
                        (if EquipCode
                            (progn
                                (setq EquipName (LEP:GetEquipLabel EquipCode))
                                (setq MasterList (LEP:AddToMasterList MasterList RouteID EquipName 1 "шт."))
                            )
                        )
                    )
                )
                (setq i (1+ i))
            )
        )
    )

    ;=================================================================
    ; ЭТАП 2.5: ОБОРУДОВАНИЕ НА СУЩЕСТВУЮЩИХ ОПОРАХ (2026-07-15)
    ;
    ; "ПУ на существующую опору" (LEP-END.LSP, третий пункт меню) НЕ
    ; создаёт новую опору - оборудование просто дописывается в XDATA
    ; УЖЕ существующей опоры (LEP:AddEquipToExistingPole, LEP-DATA.LSP),
    ; которая стоит на СЛОЕ СУЩЕСТВУЮЩИХ опор (*LEP-Layer-Exist-Pole*),
    ; а ЭТАП 2 выше сканирует ТОЛЬКО слой проектируемых
    ; (*LEP-Layer-Proj-Pole*) - без этого отдельного этапа такое
    ; оборудование вообще не попало бы в ведомость, молча.
    ;
    ; ⚠️ Статус самой ОПОРЫ тут НЕ проверяем (она и так Сущ., это её
    ; естественное состояние - не выступает материалом) - проверяем
    ; EQUIPSTATUS (статус ИМЕННО оборудования, отдельный ключ XDATA),
    ; и саму опору как "1 шт. материала" НЕ считаем вообще - только
    ; строку по EQUIP, в отличие от ЭТАПА 2 выше.
    ;=================================================================

    (setq ExistPoleSS (ssget "_X" (list '(0 . "INSERT") (cons 8 *LEP-Layer-Exist-Pole*))))

    (if ExistPoleSS
        (progn
            (setq i 0)
            (repeat (sslength ExistPoleSS)
                (setq Ent (ssname ExistPoleSS i))
                (setq EquipCode (LEP:GetDataValue Ent "EQUIP"))

                (if EquipCode
                    (progn
                        (setq EquipStatus (LEP:GetDataValue Ent "EQUIPSTATUS"))

                        (if (= EquipStatus "PROJECT")
                            (progn
                                (setq RouteID (LEP:GetDataValue Ent "ROUTE"))
                                (if (not RouteID) (setq RouteID "БЕЗ_ТРАССЫ"))

                                (setq EquipName (LEP:GetEquipLabel EquipCode))
                                (setq MasterList (LEP:AddToMasterList MasterList RouteID EquipName 1 "шт."))
                            )
                        )
                    )
                )
                (setq i (1+ i))
            )
        )
    )

    ;=================================================================
    ; ЭТАП 2.6: ПРОЕКТИРУЕМЫЕ КТП (2026-07-22)
    ;
    ; КТП - НЕ опора, но, как и опора, теперь тоже БЛОК (INSERT) - см.
    ; LEP-KTPSYM.LSP (*LEP-Block-Ktp*, прямоугольник+треугольник ОДНИМ
    ; объектом) - сканируется отдельно, на своём слое (*LEP-Layer-Proj-TP*,
    ; заведён давно, но простаивал до появления КТП). Номер КТП
    ; (свободный ввод, LEP:AddKtpData)
    ; включается в название строки - иначе разные КТП с одинаковым
    ; названием "КТП" слились бы в одну строку с суммой "2 шт." вместо
    ; двух отдельных, различимых по номеру строк.
    ;=================================================================

    (setq KtpSS (ssget "_X" (list '(0 . "INSERT") (cons 8 *LEP-Layer-Proj-TP*))))

    (if KtpSS
        (progn
            (setq i 0)
            (repeat (sslength KtpSS)
                (setq Ent (ssname KtpSS i))
                (if (= (LEP:GetDataValue Ent "TYPE") "KTP")
                    (progn
                        (setq Status (LEP:GetDataValue Ent "STATUS"))
                        (if (= Status "PROJECT")
                            (progn
                                (setq RouteID (LEP:GetDataValue Ent "ROUTE"))
                                (if (not RouteID) (setq RouteID "БЕЗ_ТРАССЫ"))

                                (setq KtpName
                                    (strcat
                                        "КТП-" (LEP:GetDataValue Ent "NUMBER")
                                        " (" (LEP:GetDataValue Ent "MARKA") ")"
                                    )
                                )
                                (setq MasterList (LEP:AddToMasterList MasterList RouteID KtpName 1 "шт."))
                            )
                        )
                    )
                )
                (setq i (1+ i))
            )
        )
    )

    ;=================================================================
    ; ЭТАП 4: ЗАПИСЬ В CSV
    ;
    ; ⚠️ ФИКС 2026-07-16: раньше здесь (ЭТАП 3) было предупреждение
    ; "чертёж сохранён не в папке с модулями LEP" - имело смысл, пока
    ; DWG был ОБЯЗАН лежать рядом с модулями (см. CLAUDE.md). Теперь,
    ; когда папка с модулями в Support File Search Path, а DWG может
    ; лежать где угодно - это стало ЛОЖНОЙ тревогой на каждой обычной
    ; выгрузке (чертёж проекта и так почти всегда лежит в СВОЕЙ папке,
    ; не в папке инструментов) - убрано целиком. CSV, как и раньше,
    ; пишется рядом с самим чертежом (DWGPREFIX) - это по-прежнему
    ; правильное поведение, папка модулей тут вообще ни при чём.
    ;=================================================================

    (setq CsvPath (strcat (getvar "DWGPREFIX") (vl-filename-base (getvar "DWGNAME")) "_ведомость.csv"))

    ;; Проверка на блокировку файла (например, открыт в Excel) - через
    ;; попытку открыть в режиме добавления, до того как стирать файл.
    (setq FileCheck (open CsvPath "a"))

    (if (not FileCheck)
        (progn
            (princ "\n!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!")
            (princ "\n[ОШИБКА] Файл ведомости заблокирован (возможно, открыт в Excel).")
            (princ "\nЗакройте файл и запустите LEP-REPORT снова.")
            (princ "\n!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!")
        )
        (progn
            (close FileCheck)
            (setq CsvFile (open CsvPath "w" "utf8-bom"))

            (write-line "Ведомость (черновая прикидка) - только проектируемые (Проект.) объекты" CsvFile)
            (write-line "Материал/оборудование;Количество;Ед. изм." CsvFile)
            (write-line "" CsvFile)

            ;; ssget "_X" отдаёт объекты не в порядке создания (похоже,
            ;; в порядке внутренней базы чертежа - на практике часто
            ;; получается обратный порядок), поэтому без сортировки
            ;; трассы в CSV шли 3-2-1 вместо 1-2-3. RouteID вида
            ;; "LEP_ROUTE_01" с ведущим нулём отлично сортируется как
            ;; обычная строка - совпадает с числовым порядком.
            (setq MasterList (vl-sort MasterList '(lambda (a b) (< (car a) (car b)))))

            ;; Блок по каждой трассе отдельно - для проектировщика
            (foreach RouteItem MasterList
                (LEP:WriteMasterListBlock CsvFile (car RouteItem) (cdr RouteItem))
                (write-line "" CsvFile)
            )

            ;; Сводный блок "ИТОГО" по всем трассам вместе - для закупки
            (setq MergedList (LEP:MergeMasterList MasterList))
            (if MergedList
                (LEP:WriteMasterListBlock CsvFile "ИТОГО" MergedList)
            )

            (close CsvFile)

            (princ "\n=======================================================")
            (princ "\n[УСПЕХ] Ведомость сохранена (UTF-8 с BOM, откроется верно и в Excel).")
            (princ (strcat "\nФайл: " CsvPath))
            (princ "\n=======================================================")
        )
    )

    (LEP:PrintFooter)
    (princ)
)


(princ "\nМодуль LEP-REPORT v1.7 загружен (КТП в ведомости).")
(princ)
