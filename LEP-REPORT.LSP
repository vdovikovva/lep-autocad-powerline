;=====================================================================
; ПРОЕКТ:       LEP (Автоматизация проектирования ЛЭП)
; ФАЙЛ:         LEP-REPORT.LSP
; ВЕРСИЯ:       1.0  (кодировка решена окончательно, с BOM для Excel - Claude)
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

    (write-line (strcat "=== " Title " ===") File)

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

        (write-line (strcat Prefix Name ";" ValueStr ";" Unit) File)
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
            (setq CsvFile (open CsvPath "w" "utf8-bom"))

            (write-line "Ведомость (черновая прикидка) - только проектируемые (Проект.) объекты" CsvFile)
            (write-line "Материал/оборудование;Количество;Ед. изм." CsvFile)
            (write-line "" CsvFile)

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


(princ "\nМодуль LEP-REPORT v1.0 загружен (структура по трассам-шапкам, UTF-8+BOM, проверка папки).")
(princ)
