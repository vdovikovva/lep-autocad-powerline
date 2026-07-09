;=====================================================================
; ПРОЕКТ:       LEP (Автоматизация проектирования ЛЭП)
; ФАЙЛ:         LEP-REPORT.LSP
; ВЕРСИЯ:       0.7  (правки по итогам теста - Claude)
;
; ПРАВКИ В ЭТОЙ ВЕРСИИ:
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
; 2. СТРУКТУРА CSV: раньше название трассы ("LEP_ROUTE_0001" или
;    "ИТОГО") повторялось в каждой строке - бессмысленно и неудобно
;    читать. Теперь название - отдельная строка-заголовок над своим
;    блоком материалов, дальше в блоке только сами материалы.
;
; 3. КОДИРОВКА (v0.6 -> v0.7, ИСПРАВЛЕНО ПОВТОРНО):
;    (write-line ...) в AutoLISP пишет не в UTF-8 - кириллица
;    превращалась в кракозябры в текстовых редакторах (Excel на Mac
;    распознавал частично за счёт своей эвристики). Первая попытка
;    (v0.6) вручную считала байты UTF-8 и писала их по одному через
;    write-char - результат оказался ещё хуже (иероглифы вместо
;    кириллицы): write-char сама кодирует переданное число в UTF-8,
;    воспринимая его как код символа, а не пишет "сырой байт" - в
;    итоге уже посчитанные вручную байты кодировались ЕЩЁ РАЗ, двойное
;    кодирование. Проверено в консоли AutoCAD: (ascii "К") = 1050 -
;    это и есть настоящий юникод-код символа (U+041A), значит write-char
;    и так ждёт юникод-код и сама кодирует его в UTF-8 - вручную
;    считать байты было не нужно, теперь просто отдаём код символа
;    через (ascii ch) как есть, без самодельной упаковки в байты.
;    Метка UTF-8 (BOM) в начале файла тоже убрана - её байты (239,
;    187, 191) по той же причине не пишутся как сырые байты, а
;    закодируются повторно, если передать их в write-char напрямую.
;
; НАЗНАЧЕНИЕ: Сбор объёмов материалов и опор (без округления) с
; разделением по трассам и экспортом в CSV.
;=====================================================================


;=====================================================================
; LEP:Utf8WriteLine
;
; Пишет одну строку текста (Text) в файл (File) - НЕ через (write-line),
; которая в AutoLISP пишет не в UTF-8 (кириллица превращалась в
; кракозябры в текстовых редакторах).
;
; ИСПРАВЛЕНО (первая версия давала ещё худший результат - иероглифы):
; Первая версия вручную считала 2 байта UTF-8 под каждый кириллический
; символ и писала оба байта через write-char по отдельности. Но
; write-char сама кодирует переданное ЧИСЛО в UTF-8, воспринимая его
; как код символа - а не пишет "сырой байт", как предполагалось.
; В результате уже посчитанные вручную байты UTF-8 (например 210 и
; 154 под "К") кодировались ЕЩЁ РАЗ, как будто это два отдельных
; символа с такими кодами - двойное кодирование, отсюда и иероглифы
; вместо кириллицы.
;
; Проверено в консоли: (ascii "К") = 1050 - это настоящий юникод-код
; символа (U+041A), а не байт старой кодировки. Значит, write-char
; и так ждёт юникод-код и сама кодирует его в UTF-8 - вручную считать
; байты не нужно, просто отдаём код символа как есть.
;=====================================================================

(defun LEP:Utf8WriteLine (Text File / i ch code)

    (setq i 0)

    (while (< i (strlen Text))
        (setq ch (substr Text (1+ i) 1))
        (setq code (ascii ch))
        (write-char code File)
        (setq i (1+ i))
    )

    (write-char 10 File)
)


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
; Для опор (Unit = "шт.") название дополняется префиксом "Опора " -
; для провода/кабеля название и так самодостаточное (например
; "СИП-2 95 мм2"), доп. префикс не нужен.
;=====================================================================

(defun LEP:WriteMasterListBlock (File Title ItemList / Item Name Value Unit ValueStr Prefix)

    (LEP:Utf8WriteLine (strcat "=== " Title " ===") File)

    (foreach Item ItemList
        (setq Name (car Item))
        (setq Value (car (cdr Item)))
        (setq Unit (cdr (cdr Item)))

        (if (= Unit "шт.")
            (progn
                (setq Prefix "Опора ")
                (setq ValueStr (itoa (fix Value)))
            )
            (progn
                (setq Prefix "")
                (setq ValueStr (rtos Value 2 2))
            )
        )

        (LEP:Utf8WriteLine (strcat Prefix Name ";" ValueStr ";" Unit) File)
    )
)


;=====================================================================
; C:LEP-REPORT - основная команда
;=====================================================================

(defun C:LEP-REPORT ( / VL-SS PoleSS i Ent RouteID Status WireName WireLength
                        PoleName MasterList MergedList CsvPath CsvFile FileCheck
                        RouteItem ModulesFolder)

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
    ; ЭТАП 2: ПРОЕКТИРУЕМЫЕ ОПОРЫ - количество по типам
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
                    )
                )
                (setq i (1+ i))
            )
        )
    )

    ;=================================================================
    ; ЭТАП 3: ПРОВЕРКА ПАПКИ ЧЕРТЕЖА
    ;
    ; Путь к CSV строится от (getvar "DWGPREFIX") - папки, где СЕЙЧАС
    ; сохранён чертёж. Если чертёж ещё не сохранён в папку с модулями
    ; LEP (или сохранён в другую папку) - CSV попадёт не туда. Ищем
    ; настоящую папку модулей через findfile (так же, как это делает
    ; LEP-START.LSP) и сравниваем - если не совпадает, честно
    ; предупреждаем, но НЕ подставляем путь самовольно и НЕ сохраняем
    ; чертёж автоматически (см. объяснение в шапке файла).
    ;=================================================================

    (setq ModulesFolder (findfile "LEP-CONFIG.LSP"))
    (if ModulesFolder
        (setq ModulesFolder (vl-filename-directory ModulesFolder))
    )

    (if (and ModulesFolder (not (wcmatch (getvar "DWGPREFIX") (strcat "*" ModulesFolder "*"))))
        (progn
            (princ "\n[LEP-REPORT] ВНИМАНИЕ: чертёж сейчас сохранён не в папке с модулями LEP.")
            (princ (strcat "\nCSV запишется рядом с чертежом: " (getvar "DWGPREFIX")))
            (princ (strcat "\nа не в папку модулей: " ModulesFolder))
            (princ "\nСохраните чертёж (Save As) в папку с модулями и запустите LEP-REPORT снова, если нужно, чтобы CSV лёг рядом с ними.")
        )
    )

    ;=================================================================
    ; ЭТАП 4: ЗАПИСЬ В CSV
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
            (setq CsvFile (open CsvPath "w"))

            (LEP:Utf8WriteLine "Ведомость (черновая прикидка) - только проектируемые (Проект.) объекты" CsvFile)
            (LEP:Utf8WriteLine "Материал/оборудование;Количество;Ед. изм." CsvFile)
            (LEP:Utf8WriteLine "" CsvFile)

            ;; Блок по каждой трассе отдельно - для проектировщика
            (foreach RouteItem MasterList
                (LEP:WriteMasterListBlock CsvFile (car RouteItem) (cdr RouteItem))
                (LEP:Utf8WriteLine "" CsvFile)
            )

            ;; Сводный блок "ИТОГО" по всем трассам вместе - для закупки
            (setq MergedList (LEP:MergeMasterList MasterList))
            (if MergedList
                (LEP:WriteMasterListBlock CsvFile "ИТОГО" MergedList)
            )

            (close CsvFile)

            (princ "\n=======================================================")
            (princ "\n[УСПЕХ] Ведомость сохранена.")
            (princ (strcat "\nФайл: " CsvPath))
            (princ "\n=======================================================")
        )
    )

    (LEP:PrintFooter)
    (princ)
)


(princ "\nМодуль LEP-REPORT v0.7 загружен (структура по трассам-шапкам, UTF-8, проверка папки).")
(princ)
