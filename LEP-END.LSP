;=====================================================================
;
;   ПРОЕКТ:      LEP
;   ФАЙЛ:        LEP-END.LSP
;   ВЕРСИЯ:      0.3  (подписи МТП разведены в стороны - Claude, 2026-07-10)
;
;   НАЗНАЧЕНИЕ:
;   Оконечное оборудование маршрута - то, чем заканчивается трасса
;   ЛЭП у заявителя (см. присланные пользователем скриншоты реальных
;   чертежей, 2026-07-10; раньше это значилось как открытая проблема
;   "Концовка маршрута не реализована" в LEP-README.md):
;
;     ПУ  (0,4 кВ, мелкий заявитель)  - 1 опора *LEP-End-PoleType*
;                                        с подписью "ПУ".
;     МТП (10 кВ, крупный заявитель)  - 3 опоры *LEP-End-PoleType*
;                                        подряд (шаг *LEP-End-MTP-
;                                        Spacing1*/-Spacing2* м),
;                                        подписи РЛК / МТП-160 кВА / ЩУ.
;
;   РЛК/МТП/ЩУ/ПУ - НЕ отдельная графика, только текстовые подписи
;   рядом с опорой (подтверждено пользователем - реальные чертежи
;   показывают именно так, без отдельных значков).
;
;   Первая опора группы (РЛК для МТП, единственная для ПУ) ставится
;   ТАК ЖЕ, как в LEP-POLE - проекция клика на ближайший отрезок
;   маршрута, вставка новой вершины, привязка GEOMCONSTRAINT - это
;   прямое продолжение трассы. Остальные опоры блока МТП (2-я и 3-я)
;   НЕ проецируются на маршрут - вставляются дальше по ТОМУ ЖЕ
;   направлению (та же логика, что разворот символа опоры, см.
;   LEP:GetPoleRotation в LEP-POLESYM.LSP), т.к. физически они уже
;   выходят за пределы нарисованной полилинии маршрута.
;
;   Тип опоры и статус для МТП/ПУ ЗАФИКСИРОВАНЫ (не спрашиваются) -
;   по прямому указанию пользователя: тип всегда *LEP-End-PoleType*
;   ("П20-3Н"), статус всегда "Проект." (существующего МТП/ПУ через
;   эту команду не бывает).
;
;=====================================================================



;=====================================================================
; C:LEP-END - основная команда
;
; Цикл: выбор типа оконечного оборудования (ПУ/МТП) -> клик точки
; рядом с концом маршрута -> установка опоры(опор) с подписями и
; данными для ведомости. Enter вместо выбора типа - выход из цикла.
;=====================================================================

(defun C:LEP-END (/ Route RouteID Choice EndType ClickPoint InsertResult
                    Pt1 Pt2 Pt3 Rotation Ent1 Ent2 Ent3 OldOs OldError)

    (setq OldError *error*)
    (defun *error* (msg)
        (if OldOs (setvar "OSMODE" OldOs))
        (setq *error* OldError)
        (princ (strcat "\nКоманда прервана: " msg))
        (princ)
    )

    (LEP:PrintHeader "Оконечное оборудование маршрута (МТП / ПУ)")

    (setq Route (car (entsel "\nВыберите полилинию маршрута: ")))

    (if Route
        (progn

            (setq RouteID (LEP:GetDataValue Route "ID"))
            (if (not RouteID) (setq RouteID "LEP_ROUTE_UNKNOWN"))

            (setq OldOs (getvar "OSMODE"))
            (setvar "OSMODE" 0)

            (princ "\nДля каждой концовки: выберите тип, затем кликните точку рядом с концом трассы.")
            (princ "\nEnter вместо выбора типа - закончить.")

            (setq Choice
                (LEP:ChooseFromList
                    (list
                        (cons "ПУ (0,4 кВ - 1 опора)" "PU")
                        (cons "МТП (10 кВ - 3 опоры: РЛК/МТП/ЩУ)" "MTP")
                    )
                    "Тип оконечного оборудования (Enter - закончить)"
                )
            )

            (while Choice

                (setq EndType (cdr Choice))
                (setq ClickPoint (getpoint "\nТочка установки (рядом с концом трассы): "))

                (if ClickPoint
                    (progn

                        ;; Первая опора - как в LEP-POLE: проекция клика на
                        ;; ближайший отрезок маршрута + новая вершина.
                        ;; Заодно получаем направление трассы в этой точке.
                        (setq InsertResult (LEP:InsertVertexOnRoute Route ClickPoint))
                        (setq Pt1 (car InsertResult))
                        (setq Rotation (LEP:GetPoleRotation (cadr InsertResult) (caddr InsertResult)))

                        (setq Ent1 (LEP:InsertPole Pt1 Rotation *LEP-End-PoleType* "PROJECT"))
                        (command "_.GEOMCONSTRAINT" "_COincident" Ent1 Pt1 Route Pt1 "")

                        ;; ⚠️ Страховка (2026-07-10, см. LEP-POLE.LSP) - пустой
                        ;; (command) закрывает GEOMCONSTRAINT, если он завис
                        ;; после неудачной попытки наложить связь, чтобы не
                        ;; портить остаток команды (2-я/3-я опора МТП, подписи).
                        (command)

                        (if (= EndType "PU")

                            (progn
                                (LEP:CreatePoleLabel Pt1 *LEP-End-PoleType* "PROJECT" *LEP-Label-PU* *LEP-Label-Angle-Default*)
                                (LEP:AddEquipData Ent1 RouteID *LEP-End-PoleType* "PU")
                                (princ "\n[LEP-END] Установлена опора с ПУ.")
                            )

                            (progn
                                ;; Опора 1 (уже вставлена выше) - РЛК. Три
                                ;; подписи блока МТП разведены в РАЗНЫЕ
                                ;; стороны (веером) - опоры стоят близко
                                ;; друг к другу (шаг 3м/2м), при одинаковом
                                ;; направлении подписи накладывались друг на
                                ;; друга (замечено пользователем на тесте).
                                (LEP:CreatePoleLabel Pt1 *LEP-End-PoleType* "PROJECT" *LEP-Label-RLK* *LEP-End-LabelAngle-RLK*)
                                (LEP:AddEquipData Ent1 RouteID *LEP-End-PoleType* "RLK")

                                ;; Опора 2 (МТП) - дальше ПО ТОМУ ЖЕ
                                ;; НАПРАВЛЕНИЮ на *LEP-End-MTP-Spacing1* м.
                                ;; НЕ проекция на маршрут - это уже за
                                ;; пределами нарисованной полилинии.
                                (setq Pt2
                                    (list
                                        (+ (car Pt1) (* *LEP-End-MTP-Spacing1* (cos Rotation)))
                                        (+ (cadr Pt1) (* *LEP-End-MTP-Spacing1* (sin Rotation)))
                                    )
                                )
                                (setq Ent2 (LEP:InsertPole Pt2 Rotation *LEP-End-PoleType* "PROJECT"))
                                (LEP:CreatePoleLabel Pt2 *LEP-End-PoleType* "PROJECT" *LEP-Label-MTP* *LEP-End-LabelAngle-MTP*)
                                (LEP:AddEquipData Ent2 RouteID *LEP-End-PoleType* "MTP")

                                ;; Опора 3 (ЩУ) - ещё дальше на
                                ;; *LEP-End-MTP-Spacing2* м от опоры 2.
                                (setq Pt3
                                    (list
                                        (+ (car Pt2) (* *LEP-End-MTP-Spacing2* (cos Rotation)))
                                        (+ (cadr Pt2) (* *LEP-End-MTP-Spacing2* (sin Rotation)))
                                    )
                                )
                                (setq Ent3 (LEP:InsertPole Pt3 Rotation *LEP-End-PoleType* "PROJECT"))
                                (LEP:CreatePoleLabel Pt3 *LEP-End-PoleType* "PROJECT" *LEP-Label-SchU* *LEP-End-LabelAngle-SchU*)
                                (LEP:AddEquipData Ent3 RouteID *LEP-End-PoleType* "SCHU")

                                (princ "\n[LEP-END] Установлен блок МТП (3 опоры: РЛК/МТП/ЩУ).")
                            )
                        )
                    )
                )

                (setq Choice
                    (LEP:ChooseFromList
                        (list
                            (cons "ПУ (0,4 кВ - 1 опора)" "PU")
                            (cons "МТП (10 кВ - 3 опоры: РЛК/МТП/ЩУ)" "MTP")
                        )
                        "Тип оконечного оборудования (Enter - закончить)"
                    )
                )
            )

            (setvar "OSMODE" OldOs)
        )
        (princ "\nМаршрут не выбран.")
    )

    (setq *error* OldError)
    (LEP:PrintFooter)
    (princ)
)


(princ "\nLEP-END v0.3 загружен (подписи РЛК/МТП/ЩУ разведены в разные стороны).")
(princ)
