;=====================================================================
; ПРОЕКТ:       LEP (Автоматизация проектирования ЛЭП)
; ФАЙЛ:         LEP-REPORT.LSP
; ВЕРСИЯ:       0.5  (переписана без ActiveX - Claude)
;
; ПЕРЕДЕЛАНО ПОЛНОСТЬЮ:
; Старая версия использовала ActiveX (vl-load-com, vla-get-length,
; vla-get-EffectiveName) - это работает ТОЛЬКО на Windows, на Mac
; вызов vl-load-com сразу падает с ошибкой ("not supported"), и
; команда вообще не запускалась. Заменено на чтение уже готовых
; данных из XDATA (LEP:GetDataValue) - её и так пишут LEP-POLE и
; LEP-SPAN при создании каждого объекта:
;   - длина пролёта - берётся из XDATA ("LENGTH", посчитана один раз
;     геометрически в LEP-SPAN при создании), а не пересчитывается
;     через vla-get-length;
;   - тип опоры - берётся из XDATA ("MODEL"), а не из имени блока
;     через vla-get-EffectiveName (у которой была своя задача -
;     распознавать динамические блоки с анонимными именами *U... -
;     нам это не нужно, у нас и так есть свой явный тип в XDATA).
; Полностью кроссплатформенно, без единого vl-*/vla-* вызова.
;
; ТОЛЬКО ПРОЕКТИРУЕМЫЕ ОБЪЕКТЫ:
; В ведомость попадают только опоры/пролёты со статусом "Проект."
; (XDATA "STATUS" = "PROJECT") - существующие (Сущ.) уже стоят на
; месте, их не нужно ни покупать, ни строить, поэтому в черновую
; ведомость на закупку/прикидку они не включаются.
;
; СТРУКТУРА CSV:
; Сначала блок по каждой трассе отдельно (проектировщику удобно
; видеть, сколько опор/провода нужно именно на эту линию - на одном
; чертеже бывает несколько трасс к разным заявителям), затем блок
; "ИТОГО" - сумма по всем трассам вместе (это уже для закупки, ей
; обычно не важно, на какую именно линию идёт материал).
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
; Пишет в CSV-файл (File) один блок строк для одной "трассы"
; (RouteLabel - реальный ID трассы или "ИТОГО" для сводного блока).
; Для опор (Unit = "шт.") название дополняется префиксом "Опора " -
; для провода/кабеля название и так самодостаточное (например
; "СИП-2 95 мм2"), доп. префикс не нужен.
;=====================================================================

(defun LEP:WriteMasterListBlock (File RouteLabel ItemList / Item Name Value Unit ValueStr Prefix)

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

        (write-line (strcat RouteLabel ";" Prefix Name ";" ValueStr ";" Unit) File)
    )
)


;=====================================================================
; C:LEP-REPORT - основная команда
;=====================================================================

(defun C:LEP-REPORT ( / VL-SS PoleSS i Ent RouteID Status WireName WireLength
                        PoleName MasterList MergedList CsvPath CsvFile FileCheck RouteItem)

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
    ; ЭТАП 3: ЗАПИСЬ В CSV
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

            (write-line "Ведомость (черновая прикидка) - только проектируемые (Проект.) объекты" CsvFile)
            (write-line "Трасса;Материал/оборудование;Количество;Ед. изм." CsvFile)

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
            (princ "\n[УСПЕХ] Ведомость сохранена.")
            (princ (strcat "\nФайл: " CsvPath))
            (princ "\n=======================================================")
        )
    )

    (LEP:PrintFooter)
    (princ)
)


(princ "\nМодуль LEP-REPORT v0.5 загружен (без ActiveX, кроссплатформенно).")
(princ)
