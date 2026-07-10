;=====================================================================
;
;   ПРОЕКТ:      LEP
;   ФАЙЛ:        LEP-END.LSP
;   ВЕРСИЯ:      0.4  (фикс направления опор МТП + одна концовка за
;                запуск - аудит Claude Fable, 2026-07-11)
;
;   ИСПРАВЛЕНО В ЭТОЙ ВЕРСИИ:
;
;   1. ⚠️ ГЕОМЕТРИЯ: опоры 2 (МТП) и 3 (ЩУ) смещались от первой опоры
;      по углу Rotation - а это угол ПОВОРОТА БЛОКА (= угол маршрута
;      МИНУС 90°, см. LEP:GetPoleRotation) - т.е. блок МТП уезжал
;      ПЕРПЕНДИКУЛЯРНО трассе, а не продолжал её, как описывал
;      пользователь ("через 3 метра вторая, ещё через 2 третья").
;      Проверено тригонометрией: cos(θ-90°)=sin θ, sin(θ-90°)=-cos θ -
;      скалярное произведение с направлением трассы равно нулю, чистый
;      перпендикуляр. Сами трапеции при этом СМОТРЕЛИ правильно
;      (поворот блока считается отдельно), поэтому в куче наложенных
;      подписей на тесте это было легко не заметить. Теперь смещение
;      считается по углу САМОГО МАРШРУТА (RouteDir), поворот блока -
;      по-прежнему по Rotation. Это два разных угла, отличаются на 90°.
;
;   2. Команда ставит ОДНУ концовку и завершается - убран цикл while
;      (по прямой просьбе пользователя 2026-07-10: "после вставки
;      оконечного блока надо закрывать команду... если надо - я ещё
;      раз запущу"; правка тогда потерялась за разбирательствами с
;      отступом LEADER, восстановлена при аудите).
;
;   НАЗНАЧЕНИЕ:
;   Оконечное оборудование маршрута - то, чем заканчивается трасса
;   ЛЭП у заявителя (см. присланные пользователем скриншоты реальных
;   чертежей, 2026-07-10):
;
;     ПУ  (0,4 кВ, мелкий заявитель)  - 1 опора *LEP-End-PoleType*
;                                        с подписью "ПУ".
;     МТП (10 кВ, крупный заявитель)  - 3 опоры *LEP-End-PoleType*
;                                        подряд (шаг *LEP-End-MTP-
;                                        Spacing1*/-Spacing2* м),
;                                        подписи РЛК / МТП-160 кВА / ЩУ,
;                                        разведённые в разные стороны
;                                        (*LEP-End-LabelAngle-*), чтобы
;                                        не накладывались.
;
;   РЛК/МТП/ЩУ/ПУ - НЕ отдельная графика, только текстовые подписи
;   рядом с опорой (подтверждено пользователем - реальные чертежи
;   показывают именно так, без отдельных значков).
;
;   Первая опора группы (РЛК для МТП, единственная для ПУ) ставится
;   ТАК ЖЕ, как в LEP-POLE - проекция клика на ближайший отрезок
;   маршрута, вставка новой вершины, привязка GEOMCONSTRAINT - это
;   прямое продолжение трассы. Остальные опоры блока МТП (2-я и 3-я)
;   НЕ проецируются на маршрут - вставляются дальше по направлению
;   трассы (за пределами нарисованной полилинии).
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
; ОДНА концовка за запуск (без цикла): выбор типа (ПУ/МТП) -> клик
; точки рядом с концом маршрута -> установка опоры(опор) с подписями
; и данными для ведомости -> команда завершается. Нужна ещё концовка
; (крайне редкий случай) - просто запустить LEP-END снова.
;=====================================================================

(defun C:LEP-END (/ Route RouteID Choice EndType ClickPoint InsertResult
                    Pt1 Pt2 Pt3 Rotation RouteDir Ent1 Ent2 Ent3 OldOs OldError)

    (setq OldError *error*)
    (defun *error* (msg)
        (if OldOs (setvar "OSMODE" OldOs))
        (setq *error* OldError)
        (princ (strcat "\nКоманда прервана: " msg))
        (princ)
    )

    (LEP:PrintHeader "Оконечное оборудование маршрута (МТП / ПУ)")

    (setq Route (car (entsel "\nВыберите полилинию маршрута (если не видна - включите LEP-ROUTEVIS): ")))

    (if Route
        (progn

            (setq RouteID (LEP:GetDataValue Route "ID"))
            (if (not RouteID) (setq RouteID "LEP_ROUTE_UNKNOWN"))

            (setq OldOs (getvar "OSMODE"))
            (setvar "OSMODE" 0)

            (setq Choice
                (LEP:ChooseFromList
                    (list
                        (cons "ПУ (0,4 кВ - 1 опора)" "PU")
                        (cons "МТП (10 кВ - 3 опоры: РЛК/МТП/ЩУ)" "MTP")
                    )
                    "Тип оконечного оборудования (Enter - отмена)"
                )
            )

            (if Choice
                (progn

                    (setq EndType (cdr Choice))
                    (setq ClickPoint (getpoint "\nТочка установки (рядом с концом трассы): "))

                    (if ClickPoint
                        (progn

                            ;; Первая опора - как в LEP-POLE: проекция клика на
                            ;; ближайший отрезок маршрута + новая вершина.
                            ;; Заодно получаем отрезок трассы под точкой - из
                            ;; него считаются ДВА РАЗНЫХ угла (см. фикс №1 в
                            ;; шапке файла, их уже один раз перепутали):
                            ;;   Rotation - угол ПОВОРОТА БЛОКА (маршрут - 90°),
                            ;;              им разворачиваются трапеции;
                            ;;   RouteDir - угол САМОГО МАРШРУТА, по нему
                            ;;              смещаются опоры 2/3 блока МТП.
                            (setq InsertResult (LEP:InsertVertexOnRoute Route ClickPoint))
                            (setq Pt1 (car InsertResult))
                            (setq Rotation (LEP:GetPoleRotation (cadr InsertResult) (caddr InsertResult)))
                            (setq RouteDir (angle (cadr InsertResult) (caddr InsertResult)))

                            (setq Ent1 (LEP:InsertPole Pt1 Rotation *LEP-End-PoleType* "PROJECT"))
                            (command "_.GEOMCONSTRAINT" "_COincident" Ent1 Pt1 Route Pt1 "")

                            ;; ⚠️ Страховка (см. LEP-POLE.LSP) - пустой (command)
                            ;; закрывает GEOMCONSTRAINT, если он завис после
                            ;; неудачной попытки наложить связь, чтобы не
                            ;; портить остаток команды (опоры 2/3, подписи).
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

                                    ;; Опора 2 (МТП) - дальше ПО НАПРАВЛЕНИЮ
                                    ;; МАРШРУТА (RouteDir, НЕ Rotation - см.
                                    ;; фикс №1 в шапке файла) на
                                    ;; *LEP-End-MTP-Spacing1* м. НЕ проекция на
                                    ;; маршрут - это уже за пределами
                                    ;; нарисованной полилинии.
                                    (setq Pt2
                                        (list
                                            (+ (car Pt1) (* *LEP-End-MTP-Spacing1* (cos RouteDir)))
                                            (+ (cadr Pt1) (* *LEP-End-MTP-Spacing1* (sin RouteDir)))
                                        )
                                    )
                                    (setq Ent2 (LEP:InsertPole Pt2 Rotation *LEP-End-PoleType* "PROJECT"))
                                    (LEP:CreatePoleLabel Pt2 *LEP-End-PoleType* "PROJECT" *LEP-Label-MTP* *LEP-End-LabelAngle-MTP*)
                                    (LEP:AddEquipData Ent2 RouteID *LEP-End-PoleType* "MTP")

                                    ;; Опора 3 (ЩУ) - ещё дальше по маршруту на
                                    ;; *LEP-End-MTP-Spacing2* м от опоры 2.
                                    (setq Pt3
                                        (list
                                            (+ (car Pt2) (* *LEP-End-MTP-Spacing2* (cos RouteDir)))
                                            (+ (cadr Pt2) (* *LEP-End-MTP-Spacing2* (sin RouteDir)))
                                        )
                                    )
                                    (setq Ent3 (LEP:InsertPole Pt3 Rotation *LEP-End-PoleType* "PROJECT"))
                                    (LEP:CreatePoleLabel Pt3 *LEP-End-PoleType* "PROJECT" *LEP-Label-SchU* *LEP-End-LabelAngle-SchU*)
                                    (LEP:AddEquipData Ent3 RouteID *LEP-End-PoleType* "SCHU")

                                    (princ "\n[LEP-END] Установлен блок МТП (3 опоры: РЛК/МТП/ЩУ).")
                                )
                            )
                        )
                        (princ "\n[LEP-END] Точка не указана - отменено.")
                    )
                )
                (princ "\n[LEP-END] Отменено.")
            )

            (setvar "OSMODE" OldOs)
        )
        (princ "\nМаршрут не выбран.")
    )

    (setq *error* OldError)
    (LEP:PrintFooter)
    (princ)
)


(princ "\nLEP-END v0.4 загружен (одна концовка за запуск, опоры МТП вдоль маршрута).")
(princ)
