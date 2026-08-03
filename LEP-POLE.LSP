;=====================================================================
;
;   ПРОЕКТ:      LEP
;   ФАЙЛ:        LEP-POLE.LSP
;   ВЕРСИЯ:      1.8  (C:LEP-POLE-MOVE переносит опору ЦЕЛИКОМ: старый
;                текст подписи и данные об оборудовании (EQUIP/
;                EQUIPSTATUS) больше не теряются - раньше опора с ПУ
;                после переноса становилась обычной и пропадала из
;                ведомости - Claude, 2026-07-28)
;   1.7  (LEP:InsertPole/PlacePoleOnRoute получили параметр
;                VClass - слой опоры теперь зависит от класса
;                напряжения маршрута, не только от статуса (4 granular
;                слоя вместо 2, см. LEP-CONFIG.LSP) - Claude, 2026-07-22)
;   1.6  (эхо расстояния сразу после клика мышкой - Dynamic
;                Input не показывает подсказку у голого getpoint,
;                Claude, 2026-07-15)
;   1.5  (LEP:BringToFront для подписи опоры, Claude, 2026-07-15)
;   1.4  (C:LEP-POLE-DELETE / C:LEP-POLE-MOVE - удаление и
;                перенос опоры целиком (подпись+откосы+блок), Claude,
;                2026-07-15)
;   1.3  (LEP:PromptNextPolePoint - направление числа
;                через знак вместо угадывания по первой опоре, Claude,
;                2026-07-15)
;   1.2  (LEP:PromptNextPolePoint - расстояние от
;                предыдущей опоры числом, Claude, 2026-07-15)
;   1.1  (LEP:CreatePoleLabel: фон под текстом выносок,
;                Claude, 2026-07-15)
;   1.0  (LEP:CreatePoleLabel: LEADER -> MLEADER, Claude, 2026-07-15)
;
;   ИСПРАВЛЕНО В ЭТОЙ ВЕРСИИ (аудит):
;   - Тип и статус опоры спрашиваются ДО вставки вершины в маршрут -
;     отмена выбора больше не оставляет лишнюю пустую вершину на
;     полилинии (раньше каждая отменённая попытка засоряла трассу).
;   - LEP:AddPoleData теперь получает НАСТОЯЩИЙ статус (был всегда
;     "PROJECT" даже для Сущ. опор - см. фикс в LEP-DATA.LSP).
;   - LEP-CatchResult объявлена локальной (утекала глобально).
;   - Подсказка про LEP-ROUTEVIS в промпте выбора маршрута.
;
;   ДОБАВЛЕНО РАНЕЕ (направление подписи параметром):
;   LEP:CreatePoleLabel получила параметр OffsetAngle (направление
;   смещения подписи, радианы) - раньше направление было зашито прямо
;   в формулу (всегда 45°, вверх-вправо). Понадобилось для LEP-END:
;   три опоры блока МТП стоят близко друг к другу, и при одинаковом
;   направлении их подписи накладывались друг на друга (замечено
;   пользователем на реальном тесте). Обычные опоры (LEP-POLE/
;   LEP-POLE-ALONE) передают *LEP-Label-Angle-Default* (те же 45°,
;   визуально ничего не изменилось).
;
;   ИСПРАВЛЕНО РАНЕЕ (баг на угловой опоре):
;   Баг: GEOMCONSTRAINT ловил конфликт "over-constrain" при установке
;   угловой опоры (клик рядом с уже существующим изломом маршрута
;   создавал вторую, почти совпадающую вершину полилинии). Исправлено
;   в LEP:InsertVertexOnRoute (снап к существующей вершине по
;   *LEP-Vertex-Snap-Tolerance*) + защитный пустой (command) после
;   GEOMCONSTRAINT в C:LEP-POLE (закрывает команду, если она всё же
;   зависнет по другой причине - иначе портился весь дальнейший цикл).
;
;   РАНЕЕ ДОБАВЛЕНО (символ-трапеция вместо test-block):
;   Вставка опоры переведена с test-block (кружок+атрибут) на новый
;   символ - трапеция+крест (LEP-POLESYM.LSP, *LEP-Block-Pole* теперь
;   указывает на него). Разворот символа считается по направлению
;   маршрута (широкая сторона к началу трассы, узкая к концу), толщина
;   линии зависит от статуса (Проект. жирнее Сущ.), а по типу опоры
;   (*LEP-PoleColumns* в CONFIG) автоматически рисуется 1/2/3 трапеции
;   (главная опора + откос(ы)). Подпись опоры теперь ДВУХСТРОЧНАЯ -
;   вторая строка это класс линии маршрута ("ВЛЗ-10 кВ"/"ВЛИ-0,4 кВ",
;   раньше эти данные на момент установки опоры были ещё неизвестны -
;   теперь класс маршрута выбирается один раз при LEP-ROUTE, доступен
;   сразу). LEP:SetBlockAttribute/ATTREQ убраны - новый символ без
;   атрибутов.
;
;   РАНЕЕ ДОБАВЛЕНО:
;   Новая команда C:LEP-POLE-ALONE - опора БЕЗ привязки к трассе
;   (вставляется ровно в клик, без проекции/вершины/GEOMCONSTRAINT,
;   свободно двигается потом). Для ведомости всё равно привязывается
;   к БЛИЖАЙШЕЙ трассе по ID (LEP:FindNearestRoute) - см. !! ПОДВОДНЫЙ
;   КАМЕНЬ !! в шапке этой функции и в LEP-README.md.
;
;   ИСПРАВЛЕНО/ПЕРЕДЕЛАНО РАНЕЕ:
;
;   ГЛАВНОЕ ИЗМЕНЕНИЕ ЛОГИКИ (по вашей просьбе):
;   Раньше опоры расставлялись АВТОМАТИЧЕСКИ по всем уже существующим
;   вершинам маршрута. Теперь пользователь сам кликает точки в цикле:
;   - клик РЯДОМ с линией маршрута (не обязательно точно в вершину);
;   - программа находит БЛИЖАЙШУЮ точку НА линии маршрута
;     (LEP:FindNearestSegment / LEP:ProjectPointOnSegment);
;   - в это место ВСТАВЛЯЕТСЯ НОВАЯ ВЕРШИНА полилинии
;     (LEP:InsertVertexOnRoute) - раньше там вершины не было;
;   - опора ставится ровно в эту новую вершину и привязывается к ней
;     геометрической связью, как и раньше.
;   - Enter без точки - выход из цикла расстановки опор.
;
;   Также в этой версии:
;   - Добавлен запрос статуса (Проект/Сущ.) для каждой опоры -
;     влияет на слой (см. *LEP-Layer-Proj-Pole* / *LEP-Layer-Exist-Pole*
;     в LEP-CONFIG.LSP).
;   - Добавлена подпись-выноска (LEADER) у каждой опоры вида
;     "Проект. оп. А23". ВНИМАНИЕ: вторая строка с классом линии и
;     напряжением ("ВЛИ-0,4 кВ" в вашем примере) сюда пока НЕ
;     добавлена - на момент установки опоры эти данные ещё не
;     известны, они появляются только после LEP-SPAN. Это открытый
;     вопрос, см. LEP-README.md.
;
;   НАЗНАЧЕНИЕ:
;   Ручная установка опор на маршрут ЛЭП, с привязкой к линии.
;
;=====================================================================
 
 
;=====================================================================
; LEP:ProjectPointOnSegment
;
; Проецирует точку P на отрезок A-B (плоская геометрия, Z не
; учитывается). Если проекция выходит за пределы отрезка - зажимает
; её к ближайшему концу (A или B).
;
; Вход: P, A, B - точки в виде (x y) или (x y z)
; Выход: точка (x y) - проекция P на отрезок A-B
;=====================================================================
 
(defun LEP:ProjectPointOnSegment (P A B / ABx ABy APx APy Dot Len2 Tt)
 
    (setq ABx (- (car B) (car A)))
    (setq ABy (- (cadr B) (cadr A)))
    (setq APx (- (car P) (car A)))
    (setq APy (- (cadr P) (cadr A)))
 
    (setq Len2 (+ (* ABx ABx) (* ABy ABy)))
 
    (if (< Len2 1e-9)
        ;; Вырожденный отрезок (A и B совпадают) - возвращаем A
        (list (car A) (cadr A))
        (progn
            (setq Tt (/ (+ (* APx ABx) (* APy ABy)) Len2))
            ;; Зажимаем параметр в пределах отрезка [0..1]
            (if (< Tt 0.0) (setq Tt 0.0))
            (if (> Tt 1.0) (setq Tt 1.0))
            (list
                (+ (car A) (* Tt ABx))
                (+ (cadr A) (* Tt ABy))
            )
        )
    )
)
 
 
;; LEP:GetVertexList убрана - дублировала LEP:GetVertices из
;; LEP-POLYLINE.LSP один в один. Везде в этом файле используется
;; LEP:GetVertices.


;=====================================================================
; LEP:FindNearestSegment
;
; Ищет, к какому отрезку маршрута ближе всего кликнутая точка.
;
; Вход:
;   Verts - список вершин (результат LEP:GetVertices)
;   P     - кликнутая точка
;
; Выход: список (Idx ProjPoint), где
;   Idx       - индекс вершины, ПОСЛЕ которой нужно вставить новую
;               (т.е. новая точка ложится между Verts[Idx] и Verts[Idx+1])
;   ProjPoint - точка проекции P на этот отрезок (x y)
;=====================================================================
 
(defun LEP:FindNearestSegment (Verts P / i A B Proj Dist BestIdx BestDist BestPoint)
 
    (setq i 0)
    (setq BestDist nil)
    (setq BestIdx 0)
    (setq BestPoint (car Verts))
 
    (while (< i (1- (length Verts)))
 
        (setq A (nth i Verts))
        (setq B (nth (1+ i) Verts))
        (setq Proj (LEP:ProjectPointOnSegment P A B))
        (setq Dist (distance P Proj))
 
        (if (or (not BestDist) (< Dist BestDist))
            (progn
                (setq BestDist Dist)
                (setq BestIdx i)
                (setq BestPoint Proj)
            )
        )
 
        (setq i (1+ i))
    )
 
    (list BestIdx BestPoint)
)
 
 
;=====================================================================
; LEP:InsertVertexOnRoute
;
; Вставляет НОВУЮ вершину в полилинию маршрута, в точке, ближайшей к
; кликнутой пользователем ClickPoint (проекция на ближайший отрезок).
;
; ВАЖНО: работает через прямую модификацию DXF-данных (entmod), без
; ActiveX и без управления командой PEDIT через командную строку -
; так надёжнее и одинаково работает на Mac и Windows. Рассчитано на
; ПРЯМЫЕ отрезки (без дуг/bulge) - для трассы ЛЭП это нормально.
;
; ⚠️ ИСПРАВЛЕНО 2026-07-10 (баг найден на угловой опоре): если клик
; пришёлся РЯДОМ С УЖЕ СУЩЕСТВУЮЩЕЙ вершиной маршрута (а угловые опоры
; почти всегда ставятся именно в реальный излом трассы, где вершина
; уже есть) - раньше сюда всё равно вставлялась ВТОРАЯ, почти
; совпадающая вершина. На этом участке полилинии получался вырожденный
; (нулевой длины) отрезок, и когда GEOMCONSTRAINT пытался ещё и
; "приклеить" туда опору - решатель ограничений ловил конфликт
; "over-constrain" (диалог "Geometric Constraints" в AutoCAD). Теперь,
; если спроецированная точка ближе *LEP-Vertex-Snap-Tolerance* м к
; уже существующей вершине отрезка - НОВАЯ вершина не вставляется
; вообще, используется существующая как есть (см. cond ниже).
;
; Вход:
;   RouteEnt   - ename полилинии маршрута
;   ClickPoint - точка, которую кликнул пользователь
;
; Выход: список (Точка SegStart SegEnd) - точка, куда ставить опору
; (либо новая вершина, либо уже существующая, если попали в снап), и
; концы отрезка маршрута под ней (для разворота символа опоры).
;=====================================================================

(defun LEP:InsertVertexOnRoute (RouteEnt ClickPoint / Verts Found Idx NewPt SegStart SegEnd NewVerts i V NewEList Item VertexInserted)

    (setq Verts (LEP:GetVertices RouteEnt))
    (setq Found (LEP:FindNearestSegment Verts ClickPoint))
    (setq Idx (car Found))
    (setq NewPt (cadr Found))

    ;; Запоминаем концы ОТРЕЗКА, на который легла новая вершина - ДО
    ;; того, как список вершин поменяется вставкой. Нужно для разворота
    ;; символа опоры по направлению маршрута (LEP:GetPoleRotation,
    ;; LEP-POLESYM.LSP) - широкая сторона трапеции должна смотреть к
    ;; началу маршрута, узкая - к концу (по просьбе пользователя).
    (setq SegStart (nth Idx Verts))
    (setq SegEnd (nth (1+ Idx) Verts))

    (cond

        ;; Точка совпадает (почти) с началом отрезка - уже существующая
        ;; вершина маршрута (реальный излом трассы). НЕ создаём вторую
        ;; точку в том же месте - см. ⚠️ в шапке функции выше.
        ((< (distance NewPt SegStart) *LEP-Vertex-Snap-Tolerance*)
            (list SegStart SegStart SegEnd)
        )

        ;; Точка совпадает (почти) с концом отрезка - аналогично.
        ((< (distance NewPt SegEnd) *LEP-Vertex-Snap-Tolerance*)
            (list SegEnd SegStart SegEnd)
        )

        ;; Обычный случай - точка на прямом участке, вставляем новую
        ;; вершину как раньше.
        (t

            ;; Собираем новый список вершин со вставленной точкой сразу после Idx
            (setq NewVerts nil)
            (setq i 0)
            (foreach V Verts
                (setq NewVerts (append NewVerts (list V)))
                (if (= i Idx)
                    (setq NewVerts (append NewVerts (list NewPt)))
                )
                (setq i (1+ i))
            )

            ;; Перестраиваем DXF-данные полилинии:
            ;; - на месте ПЕРВОГО встреченного (10 . ...) вставляем ВЕСЬ новый
            ;;   список вершин по порядку;
            ;; - остальные старые (10 . ...) пропускаем (они уже учтены выше);
            ;; - код 90 (счётчик вершин) обновляем на новое количество.
            (setq NewEList nil)
            (setq VertexInserted nil)

            (foreach Item (entget RouteEnt)
                (cond

                    ((= (car Item) 10)
                     (if (not VertexInserted)
                         (progn
                             (foreach NV NewVerts
                                 (setq NewEList (append NewEList (list (cons 10 NV))))
                             )
                             (setq VertexInserted T)
                         )
                     )
                     ;; остальные (10 . ...) просто пропускаем, ничего не добавляем
                    )

                    ((= (car Item) 90)
                     (setq NewEList (append NewEList (list (cons 90 (length NewVerts)))))
                    )

                    (t
                     (setq NewEList (append NewEList (list Item)))
                    )

                )
            )

            (entmod NewEList)
            (entupd RouteEnt)

            ;; Возвращаем НЕ только точку, а точку + концы отрезка маршрута,
            ;; на который она легла - вызывающая сторона (C:LEP-POLE) считает
            ;; по ним угол разворота символа опоры.
            (list NewPt SegStart SegEnd)
        )
    )
)
 
 
;=====================================================================
; LEP:GetPoleType-CmdLine
;
; Запасной способ выбора типа опоры - через командную строку,
; номером. Используется, если DCL-диалог недоступен/не открылся
; (а с недавних пор - как основной способ, см. *LEP-UseDCL* в
; CONFIG). Само меню (построение списка номер-название, столбиком)
; теперь общее с выбором марки провода/кабеля в LEP-SPAN - см.
; LEP:ChooseFromList в LEP-UTILS.LSP, чтобы не держать два разных
; места с одной и той же логикой.
;
; Возвращает: строку с типом опоры, либо nil при отмене (Esc).
;=====================================================================

(defun LEP:GetPoleType-CmdLine (/ Result)
    (setq Result (LEP:ChooseFromList *LEP-PoleTypes* "Номер опоры"))
    (if Result
        (car Result)
    )
)
 
 
;=====================================================================
; LEP:GetPoleType-DCL
;
; Основной способ выбора типа опоры - настоящий диалог AutoCAD со
; списком (LEP-POLE.DCL), по которому можно кликнуть мышкой, а не
; вводить номер руками. Список заполняется из *LEP-PoleTypes*.
;
; Если файл LEP-POLE.DCL не найден или диалог не открылся - тихо
; переключается на LEP:GetPoleType-CmdLine, чтобы работа не
; останавливалась.
;
; Возвращает: строку с типом опоры, либо nil при отмене.
;=====================================================================
 
(defun LEP:GetPoleType-DCL (/ DclFile dcl_id SelIdx DlgOK Result Item)
 
    (setq DclFile (findfile "LEP-POLE.DCL"))
 
    (if (not DclFile)
        (progn
            (princ "\n[LEP-POLE] Файл LEP-POLE.DCL не найден - использую ввод номером.")
            (LEP:GetPoleType-CmdLine)
        )
        (progn
            (setq dcl_id (load_dialog DclFile))
 
            (if (not (new_dialog "lep_pole_dialog" dcl_id))
                (progn
                    (princ "\n[LEP-POLE] Не удалось открыть диалог - использую ввод номером.")
                    (if dcl_id (unload_dialog dcl_id))
                    (LEP:GetPoleType-CmdLine)
                )
                (progn
                    ;; Заполняем список названиями типов опор из CONFIG
                    (start_list "pole_list")
                    (foreach Item *LEP-PoleTypes*
                        (add_list (car Item))
                    )
                    (end_list)
 
                    (set_tile "pole_list" "0") ; по умолчанию выделен первый пункт
                    (setq SelIdx 0)
                    (setq DlgOK nil)
 
                    (action_tile "pole_list" "(setq SelIdx (atoi $value))")
                    (action_tile "accept" "(setq DlgOK T) (done_dialog)")
                    (action_tile "cancel" "(setq DlgOK nil) (done_dialog)")
 
                    (start_dialog)
                    (unload_dialog dcl_id)
 
                    (setq Result nil)
                    (if (and DlgOK SelIdx)
                        (setq Result (car (nth SelIdx *LEP-PoleTypes*)))
                    )
                    Result
                )
            )
        )
    )
)
 
 
;=====================================================================
; LEP:GetPoleType
;
; Диспетчер: выбирает DCL-диалог или ввод номером в зависимости от
; настройки *LEP-UseDCL* в LEP-CONFIG.LSP (по умолчанию - консоль,
; см. CONFIG).
;
; РАНЬШЕ здесь была проверка (boundp '*LEP-UseDCL*) "на всякий
; случай, вдруг конфиг не загрузился" - но она давала обратный
; эффект: если *LEP-UseDCL* по какой-то причине не была установлена
; (например LEP-CONFIG.LSP не тот, что ожидался - findfile мог найти
; чужую копию файла раньше нашей в путях поиска AutoCAD), boundp
; возвращал nil, и весь (and ...) тоже становился nil - код тихо
; уходил в DCL-диалог, а не в консольное меню, даже когда пользователь
; явно поставил *LEP-UseDCL* nil в правильном конфиге. При этом
; команда "!*LEP-UseDCL*" в консоли AutoCAD в обоих случаях ("явно
; nil" и "вообще не установлена") печатает одно и то же "nil" -
; поэтому баг было не поймать простой проверкой значения.
;
; boundp тут был не нужен в принципе: в AutoLISP обращение к
; необъявленной переменной само по себе безопасно и возвращает nil
; (в отличие от Common Lisp, ошибки не будет) - так что "не
; установлена" и "установлена в nil" и так ведут себя одинаково.
;=====================================================================

(defun LEP:GetPoleType ()
    (if (not *LEP-UseDCL*)
        (LEP:GetPoleType-CmdLine)
        (LEP:GetPoleType-DCL)
    )
)
 
 
;=====================================================================
; LEP:GetPoleStatus
;
; Запрашивает статус опоры: Проект или Существующая.
; Возвращает "PROJECT" или "EXIST". Сама логика теперь общая -
; см. LEP:GetStatus в LEP-UTILS.LSP (используется и в LEP-SPAN).
;=====================================================================

(defun LEP:GetPoleStatus ()
    (LEP:GetStatus "опоры")
)
 
 
;=====================================================================
; LEP:InsertPole
;
; Вставка символа опоры (трапеция + крест, LEP-POLESYM.LSP) в точку
; Point с разворотом Rotation (радианы) - переключает слой по статусу
; и делегирует саму вставку LEP:InsertPoleGroup, которая по типу опоры
; сама решает, сколько трапеций рисовать (1/2/3, см. *LEP-PoleColumns*
; в CONFIG). Толщина линии по статусу (Проект./Сущ.) выставляется
; внутри LEP:InsertPoleSymbol - здесь этим заниматься не нужно.
;
; РАНЬШЕ здесь была запись типа опоры в АТРИБУТ блока (test-block,
; тег TIP) - новый символ опоры БЕЗ атрибутов (подписи - отдельным
; текстом, LEP:CreatePoleLabel, как и раньше), поэтому ATTREQ/
; LEP:SetBlockAttribute больше не нужны и убраны отсюда целиком.
;=====================================================================

;; ⚠️ ФИКС 2026-07-22 (по просьбе пользователя - цвет опоры зависит от
;; класса напряжения, не только от статуса): добавлен параметр VClass
;; ("10"/"04", см. *LEP-VoltageClasses* в CONFIG) - выбирает ОДИН из
;; ЧЕТЫРЁХ granular слоёв опор вместо одного из двух. VClass может быть
;; nil (например LEP-POLE-ALONE на чертеже без единой трассы, привязать
;; не к чему) - в этом случае используется 10кВ как безопасный дефолт
;; (тот же слой, что был единственным ДО этой правки).
(defun LEP:InsertPole (Point Rotation PoleType Status VClass / OldLayer Ent TargetLayer)

    (setq OldLayer (getvar "CLAYER"))

    (if (= Status "EXIST")
        (if (= VClass "04")
            (setq TargetLayer *LEP-Layer-Exist-Pole-04*)
            (setq TargetLayer *LEP-Layer-Exist-Pole-10*)
        )
        (if (= VClass "04")
            (setq TargetLayer *LEP-Layer-Proj-Pole-04*)
            (setq TargetLayer *LEP-Layer-Proj-Pole-10*)
        )
    )
    (LEP:SetCurrentLayer TargetLayer)

    (setq Ent (LEP:InsertPoleGroup Point Rotation PoleType Status))

    (setvar "CLAYER" OldLayer)

    Ent
)
 
 
;=====================================================================
; LEP:CreatePoleLabel
;
; Подпись-выноска (MLEADER, было LEADER до 2026-07-15) рядом с опорой.
;
; ТЕПЕРЬ ДВЕ СТРОКИ (было однострочно, см. историю версий файла):
; первая - статус+тип ("Проект. оп. А20-3Н"), вторая - класс линии
; ("ВЛЗ-10 кВ"/"ВЛИ-0,4 кВ", ClassLabel) - берётся из класса
; напряжения МАРШРУТА (*LEP-VoltageClassLabel* в CONFIG), который
; теперь известен СРАЗУ при установке опоры (выбирается один раз при
; LEP-ROUTE, а не после LEP-SPAN, как раньше не хватало данных).
;
; ClassLabel может быть nil (например LEP-POLE-ALONE, если на
; чертеже вообще нет ни одной трассы, привязать не к чему) - тогда
; вторая строка просто не добавляется, подпись остаётся однострочной.
;
; ⚠️ МИГРАЦИЯ 2026-07-15: LEADER заменён на MLEADER (см. подробное
; обоснование и живые тесты в LEP-CONFIG.LSP, раздел "СТИЛЬ ВЫНОСОК
; MLEADER" - короче: стрелка+полка+текст теперь ОДИН объект, и текст
; можно закрепить лежащим НА полке/подчёркнутым - настройками стиля
; "Standard", LEP:CreateMLeaderStyle в LEP-SETUP.LSP). MLEADER проще в
; вызове, чем LEADER: две точки + текст ОДНОЙ строкой - никаких
; повторяющихся "пусто/текст/пусто" ответов, как раньше. Многострочный
; текст (статус+тип опоры / класс линии) - через код разрыва абзаца
; MTEXT "\P" ПРЯМО ВНУТРИ строки текста (протестировано живьём,
; работает и с кириллицей): "\\P" в AutoLISP-строке - это ДВА символа
; на выходе (обратный слэш + P), т.к. "\\" в исходнике - экранированный
; одиночный слэш.
;
; OffsetAngle (радианы) - НАПРАВЛЕНИЕ, куда уходит подпись от опоры.
; Добавлено 2026-07-10: у обычных опор всегда 45° (вверх-вправо,
; *LEP-Label-Angle-Default* в CONFIG - то же самое смещение, что было
; раньше, когда направление было зашито прямо в формулу). Понадобилось,
; чтобы у блока МТП (LEP-END.LSP, 3 опоры близко друг к другу) можно
; было развести три подписи в РАЗНЫЕ стороны - иначе накладываются
; друг на друга (замечено пользователем на реальном тесте).
;=====================================================================

(defun LEP:CreatePoleLabel (Point PoleType Status ClassLabel OffsetAngle / StatusText LabelText TextPoint OldLayer LabelEnt)

    (setq OldLayer (getvar "CLAYER"))
    (LEP:SetCurrentLayer *LEP-Layer-Text*)

    (if (= Status "EXIST")
        (setq StatusText "Сущ.")
        (setq StatusText "Проект.")
    )

    (setq LabelText (strcat StatusText " оп. " PoleType))

    ;; Точка для текста - со смещением от опоры на *LEP-LeaderOffset*
    ;; м, в направлении OffsetAngle, чтобы не накладывалась на сам блок
    ;; (и на соседние подписи, если направление задано специально).
    (setq TextPoint
        (list
            (+ (car Point) (* *LEP-LeaderOffset* (cos OffsetAngle)))
            (+ (cadr Point) (* *LEP-LeaderOffset* (sin OffsetAngle)))
        )
    )

    (if ClassLabel
        (command "_.MLEADER" Point TextPoint (strcat LabelText "\\P" ClassLabel))
        (command "_.MLEADER" Point TextPoint LabelText)
    )

    (setq LabelEnt (entlast))

    ;; Фон под текстом - свойство КАЖДОЙ выноски отдельно, не стиля
    ;; (см. LEP-CONFIG.LSP, раздел "ФОНОВАЯ МАСКА ТЕКСТА ВЫНОСОК").
    (LEP:SetMLeaderBackgroundMask LabelEnt)

    ;; Порядок отрисовки - наверх (по просьбе пользователя 2026-07-15,
    ;; см. LEP:BringToFront, LEP-UTILS.LSP).
    (LEP:BringToFront LabelEnt)

    (setvar "CLAYER" OldLayer)

    ;; ⚠️ ДОБАВЛЕНО 2026-07-15: возвращаем ename созданной подписи -
    ;; нужно для LEP:AddPoleData (хранит хендл подписи в XDATA опоры,
    ;; см. LEP-DATA.LSP) - LEP-POLE-DELETE/LEP-POLE-MOVE не могли бы
    ;; иначе найти и убрать подпись при удалении/переносе опоры (это
    ;; отдельный, никак не связанный с блоком опоры объект). Раньше
    ;; возвращалось то, что вернёт setvar (OldLayer) - никем не
    ;; использовалось, ломать было нечего.
    LabelEnt
)


;=====================================================================
; LEP:PromptNextPolePoint
;
; Точка следующей опоры - ДВА способа получить, по просьбе
; пользователя 2026-07-15 (раньше было только "на глаз" мышкой, потом
; вручную двигать опоры под нужный шаг - и для Сущ. по изысканиям, и
; для Проект. по проектной норме шага пользователь и так знает нужное
; расстояние ДО клика):
;
;   1. Если PrevPoint ещё нет (это САМАЯ ПЕРВАЯ опора сессии - мерить
;      не от чего) - обычный клик мышкой, как раньше.
;   2. Иначе - СНАЧАЛА спрашивает расстояние ЧИСЛОМ СО ЗНАКОМ (getreal -
;      клик мышкой по обычному поведению AutoLISP тут просто
;      игнорируется, ждёт клавиатуру). ЗНАК = направление вдоль трассы:
;      "+" - в сторону, ПРОТИВОПОЛОЖНУЮ подписи "Маршрут NN" (она стоит
;      у ПЕРВОЙ вершины маршрута, LEP-ROUTE.LSP), "-" - обратно, В
;      СТОРОНУ подписи. Готовый бесплатный ориентир на чертеже - другой
;      визуализации направления не понадобилось (гуглил - штатной
;      "стрелочной" линии в AutoCAD нет, а самодельная линия ровно та
;      же морока, из-за которой убрали LEP_CABLE).
;      ⚠️ ФИКС 2026-07-15: раньше направление угадывалось ОДИН раз по
;      тому, к какой вершине маршрута ближе ПЕРВАЯ опора - ломалось,
;      если первая опора стояла у СЕРЕДИНЫ трассы (сравнение расстояний
;      сводилось к случайным долям миллиметра, направление было
;      непредсказуемым). Знак числа убирает эту угадайку целиком - надо
;      всегда явно, никакого "запоминания направления между опорами"
;      больше нет.
;      Если Enter (не ввели число) - обычный клик мышкой, НО с базовой
;      точкой PrevPoint - AutoCAD рисует резинку от предыдущей опоры
;      до курсора (это безусловная фишка getpoint с базовой точкой).
;      ⚠️ ФИКС 2026-07-15 (проверено пользователем вживую): "числовая"
;      подсказка Dynamic Input (расстояние/угол у курсора), на которую
;      рассчитывали раньше - НЕ появляется у голого getpoint из LISP -
;      похоже, это фишка только штатных команд (LINE и т.п.), а не
;      честная настройка, которую можно включить. Раз "живого" числа
;      во время протаскивания не выходит бесплатно - показываем
;      фактическое расстояние СРАЗУ ПОСЛЕ клика (не во время
;      протаскивания, но хотя бы сразу видно, что получилось, без
;      ручного замера).
;
; ⚠️ НЕ проверено вживую, что getreal гарантированно игнорирует клик
; мышкой (а не пытается интерпретировать его как-то ещё) - это
; стандартное, задокументированное поведение AutoLISP, но именно ЭТОТ
; частный случай в этом проекте живьём не тестировался - проверить при
; первом реальном использовании.
;=====================================================================

(defun LEP:PromptNextPolePoint (Route PrevPoint / DistInput RouteVerts PrevIdx ClickResult)

    (if (not PrevPoint)

        (getpoint "\nТочка опоры (Enter - закончить): ")

        (progn
            (initget 0)
            (setq DistInput
                (getreal "\nРасстояние от предыдущей опоры, м (+ от подписи \"Маршрут NN\", - к ней; Enter - точка мышкой): ")
            )

            (if (and DistInput (= DistInput 0))
                (princ "\n[LEP-POLE] Расстояние не может быть нулевым - укажите точку мышкой.")
            )

            (if (and DistInput (/= DistInput 0))

                (progn
                    (setq RouteVerts (LEP:GetVertices Route))
                    (setq PrevIdx (LEP:GetNearestVertexIndex RouteVerts PrevPoint))
                    (LEP:GetPointAtDistance RouteVerts PrevIdx (abs DistInput) (>= DistInput 0))
                )

                (progn
                    (setq ClickResult (getpoint PrevPoint "\nТочка опоры (Enter - закончить): "))

                    ;; Расстояние СРАЗУ после клика - см. ФИКС 2026-07-15
                    ;; в шапке функции (живая подсказка не появляется).
                    (if ClickResult
                        (princ
                            (strcat
                                "\n[LEP-POLE] Расстояние до предыдущей опоры: "
                                (rtos (distance PrevPoint ClickResult) 2 2)
                                " м"
                            )
                        )
                    )

                    ClickResult
                )
            )
        )
    )
)


;=====================================================================
; LEP:PlacePoleOnRoute
;
; Общая логика вставки ОДНОЙ опоры на трассу - выделена 2026-07-15 из
; C:LEP-POLE (была только там), чтобы её же мог использовать
; C:LEP-POLE-MOVE (перенос = удалить старую + вставить новую этой же
; функцией на новом месте, без дублирования кода в двух местах):
; проекция клика на трассу -> новая вершина -> блок опоры -> привязка
; GEOMCONSTRAINT -> подпись -> данные для ведомости (включая хендл
; подписи - см. LEP:AddPoleData, LEP-DATA.LSP).
;
; Возвращает ename ГЛАВНОЙ трапеции опоры, либо nil, если вставка не
; удалась (LEP:InsertPole сама решает, когда это происходит).
;=====================================================================

(defun LEP:PlacePoleOnRoute (Route RouteID ClassLabel ClickPoint PoleType Status VClass / InsertResult NewVertex Rotation PoleEnt LabelEnt)

    ;; Находим ближайшую точку на линии и вставляем туда новую вершину
    ;; полилинии. Заодно получаем концы отрезка маршрута под ней -
    ;; нужны для разворота символа опоры по направлению трассы.
    (setq InsertResult (LEP:InsertVertexOnRoute Route ClickPoint))
    (setq NewVertex (car InsertResult))
    (setq Rotation (LEP:GetPoleRotation (cadr InsertResult) (caddr InsertResult)))

    ;; Вставляем символ опоры (1/2/3 трапеции по типу) в новую вершину.
    (setq PoleEnt (LEP:InsertPole NewVertex Rotation PoleType Status VClass))

    (if PoleEnt
        (progn
            ;; Привязываем ГЛАВНУЮ трапецию к вершине маршрута (откосы,
            ;; если есть, не привязаны - чисто визуальная деталь).
            (command "_.GEOMCONSTRAINT" "_COincident" PoleEnt NewVertex Route NewVertex "")

            ;; ⚠️ Страховка (2026-07-10): если GEOMCONSTRAINT всё же не
            ;; смог наложить связь (диалог "Geometric Constraints" в
            ;; AutoCAD) - команда сама по себе НЕ завершается, а
            ;; остаётся ждать повторного выбора объекта ("Press OK to
            ;; reselect..."). Пустой (command) - это Escape в AutoLISP,
            ;; гарантированно закрывает любую всё ещё активную команду,
            ;; чтобы один неудачный констрейнт не портил остальное (см.
            ;; переписку с пользователем про "Select object:
            ;; _.GEOMCONSTRAINT").
            (command)

            ;; Подпись-выноска (2 строки) - хендл возвращается функцией
            ;; и уходит в XDATA опоры (см. LEP:AddPoleData).
            (setq LabelEnt (LEP:CreatePoleLabel NewVertex PoleType Status ClassLabel *LEP-Label-Angle-Default*))

            ;; Данные для ведомости + хендл подписи (для
            ;; LEP-POLE-DELETE/LEP-POLE-MOVE).
            (LEP:AddPoleData PoleEnt RouteID PoleType Status LabelEnt)
        )
    )

    PoleEnt
)


;=====================================================================
; C:LEP-POLE - основная команда
;
; РУЧНАЯ расстановка опор в цикле. Каждый клик - это:
; проекция на линию -> новая вершина -> блок опоры -> тип -> статус
; -> связь с линией -> подпись -> данные для ведомости.
; Enter без точки - выход из цикла.
;=====================================================================
 
;; LEP-CatchResult в списке локальных (⚠️ ФИКС 2026-07-11, аудит):
;; раньше не был объявлен и утекал глобальной переменной - безвредно
;; само по себе, но ровно этот класс неявных глобалов уже давал
;; трудноуловимый баг с *LEP-UseDCL*/boundp (см. LEP:GetPoleType).
(defun C:LEP-POLE (/ Route RouteID VClass ClassLabel OldOs OldError ClickPoint InsertResult NewVertex Rotation PoleType Status PoleEnt LEP-CatchResult PrevPoint)
 
    (setq OldError *error*)
    (defun *error* (msg)
        (if OldOs (setvar "OSMODE" OldOs))
        (setq *error* OldError)
        (princ (strcat "\nКоманда прервана: " msg))
        (princ)
    )
 
    (LEP:PrintHeader "Установка опор (ручная)")
 
    (setq Route (car (entsel "\nВыберите полилинию маршрута (если не видна - включите LEP-ROUTEVIS): ")))

    (if Route
        (progn

            (setq RouteID (LEP:GetDataValue Route "ID"))
            (if (not RouteID) (setq RouteID "LEP_ROUTE_UNKNOWN"))

            ;; Класс линии для второй строки подписи опоры - берём ОДИН
            ;; РАЗ здесь (класс напряжения не меняется вдоль одного
            ;; маршрута, см. LEP-ROUTE.LSP), а не на каждой опоре.
            (setq VClass (LEP:GetDataValue Route "VCLASS"))
            (setq ClassLabel (cdr (assoc VClass *LEP-VoltageClassLabel*)))

            (setq OldOs (getvar "OSMODE"))
            (setvar "OSMODE" 0)
 
            (princ "\nКликайте точки установки опор рядом с трассой.")
            (princ "\nEnter без точки - закончить.")
            (princ "\nНачиная со 2-й опоры: расстояние числом (+ от подписи \"Маршрут NN\", - к ней).")

            (setq ClickPoint (LEP:PromptNextPolePoint Route PrevPoint))

            (while ClickPoint
 
                ;; Вся обработка одной точки обёрнута в vl-catch-all-apply:
                ;; если что-то внутри пойдёт не так (например,
                ;; GEOMCONSTRAINT не сможет наложить связь) - команда
                ;; НЕ прерывается целиком, а просто предупреждает и
                ;; переходит к следующей точке. Раньше любая ошибка
                ;; внутри цикла обрывала всю расстановку опор.
                (setq LEP-CatchResult
                    (vl-catch-all-apply
                        '(lambda ()

                            ;; 1. Спрашиваем тип и статус опоры - ДО
                            ;;    вставки вершины (⚠️ ФИКС 2026-07-11,
                            ;;    аудит: раньше вершина вставлялась в
                            ;;    полилинию ПЕРВОЙ, до вопросов - отмена
                            ;;    выбора типа (Enter/Esc) оставляла на
                            ;;    маршруте лишнюю "пустую" вершину без
                            ;;    опоры при каждой отменённой попытке).
                            ;;    Тип и статус от геометрии не зависят,
                            ;;    порядок вопросов безопасно менять.
                            (setq PoleType (LEP:GetPoleType))

                            (if PoleType
                                (progn
                                    (setq Status (LEP:GetPoleStatus))

                                    ;; 2-6. Вся геометрия+констрейнт+подпись+
                                    ;;      данные - общая функция (см. её
                                    ;;      шапку выше), используется и в
                                    ;;      C:LEP-POLE-MOVE.
                                    (setq PoleEnt (LEP:PlacePoleOnRoute Route RouteID ClassLabel ClickPoint PoleType Status VClass))

                                    ;; 7. Запоминаем точку - от неё будет
                                    ;;    отсчитываться расстояние для
                                    ;;    следующей опоры (знаком числа -
                                    ;;    см. ФИКС 2026-07-15 в шапке
                                    ;;    LEP:PromptNextPolePoint; направление
                                    ;;    больше НЕ запоминается между
                                    ;;    опорами - задаётся явно каждый раз).
                                    (if PoleEnt
                                        (setq PrevPoint (cdr (assoc 10 (entget PoleEnt))))
                                    )
                                )
                            )
                        )
                     '())
                )

                (if (vl-catch-all-error-p LEP-CatchResult)
                    (princ
                        (strcat
                            "\n[LEP-POLE] Ошибка на этой точке, пропускаю и продолжаю: "
                            (vl-catch-all-error-message LEP-CatchResult)
                        )
                    )
                )

                (setq ClickPoint (LEP:PromptNextPolePoint Route PrevPoint))
            )
 
            (setvar "OSMODE" OldOs)
        )
        (princ "\nМаршрут не выбран.")
    )
 
    (setq *error* OldError)
    (LEP:PrintFooter)
    (princ)
)


;=====================================================================
; LEP:DeletePoleGroup
;
; Полностью убирает опору - подпись + откосы (если есть) + сама
; главная трапеция. Нужна и для C:LEP-POLE-DELETE, и для
; C:LEP-POLE-MOVE (перенос = удалить старую этой функцией + вставить
; новую через LEP:PlacePoleOnRoute).
;
; ⚠️ Найдено пользователем 2026-07-15: (entdel) на блоке опоры НЕ
; трогает её подпись (отдельный объект MLEADER, никакой связи между
; ними в AutoCAD нет) - подтверждено живым тестом, подпись остаётся
; висеть в воздухе, указывая на пустое место. Поэтому подпись убираем
; ОТДЕЛЬНО, по хендлу, сохранённому в XDATA опоры при вставке (см.
; LEP:AddPoleData, LEP-DATA.LSP).
;
; Откосы (у анкерных/угловых опор, 2/3 столба) - НЕ имеют своей XDATA
; вообще (см. LEP:InsertPoleGroup, LEP-POLESYM.LSP - данные пишутся
; только на главную трапецию) - это и есть надёжный признак "это
; откос, не отдельная опора", а не хрупкая близость к главной. Ищем
; блоки *LEP-Block-Pole* в окне вокруг главной трапеции (с запасом
; поверх *LEP-Pole-Sym-Offset*) и убираем те, у которых XDATA нет.
;
; ⚠️ Вершину трассы, к которой была привязана опора, НЕ трогаем -
; она на служебном скрытом слое, не печатается, в ведомость не
; попадает - безвредный технический "хвостик". Гоняться за её
; удалением опаснее (риск случайно задеть чужую вершину - от соседней
; опоры или родного излома маршрута), чем оставить как есть.
;=====================================================================

(defun LEP:DeletePoleGroup (PoleEnt / PolePt LabelHandle LabelEnt Radius Corner1 Corner2 SS i Ent)

    (setq PolePt (cdr (assoc 10 (entget PoleEnt))))

    ;; Подпись - по хендлу из XDATA.
    (setq LabelHandle (LEP:GetDataValue PoleEnt "LABELHANDLE"))
    (if LabelHandle
        (progn
            (setq LabelEnt (handent LabelHandle))
            (if LabelEnt (entdel LabelEnt))
        )
    )

    ;; Откосы - блоки того же имени, БЕЗ XDATA, в окне вокруг опоры.
    (setq Radius (* *LEP-Pole-Sym-Offset* 1.5))
    (setq Corner1 (list (- (car PolePt) Radius) (- (cadr PolePt) Radius)))
    (setq Corner2 (list (+ (car PolePt) Radius) (+ (cadr PolePt) Radius)))

    (setq SS (ssget "_C" Corner1 Corner2 (list (cons 0 "INSERT") (cons 2 *LEP-Block-Pole*))))
    (if SS
        (progn
            (setq i 0)
            (repeat (sslength SS)
                (setq Ent (ssname SS i))
                (if (and (/= Ent PoleEnt) (not (LEP:GetDataValue Ent "TYPE")))
                    (entdel Ent)
                )
                (setq i (1+ i))
            )
        )
    )

    ;; Сама главная трапеция - последней.
    (entdel PoleEnt)
)


;=====================================================================
; C:LEP-POLE-DELETE
;
; Удаляет опору целиком (подпись + откосы + блок) - клик по ГЛАВНОЙ
; трапеции опоры. Добавлено 2026-07-15 по прямой просьбе пользователя:
; раньше единственный способ убрать неправильно поставленную опору -
; вручную стереть блок мышкой, оставляя висящую подпись (и откосы у
; анкерных/угловых опор) мусором на чертеже.
;=====================================================================

(defun C:LEP-POLE-DELETE (/ PickResult Ent OldError)

    (setq OldError *error*)
    (defun *error* (msg)
        (setq *error* OldError)
        (princ (strcat "\nКоманда прервана: " msg))
        (princ)
    )

    (LEP:PrintHeader "Удаление опоры (с подписью и откосами)")

    (setq PickResult (entsel "\nКликните по опоре для удаления: "))

    (if PickResult
        (progn
            (setq Ent (car PickResult))
            (if (and (= (cdr (assoc 0 (entget Ent))) "INSERT")
                     (= (LEP:GetDataValue Ent "TYPE") "POLE")
                )
                (progn
                    (LEP:DeletePoleGroup Ent)
                    (princ "\n[LEP-POLE-DELETE] Опора, подпись и откосы (если были) удалены.")
                )
                (princ "\n[LEP-POLE-DELETE] Это не опора (возможно, откос или посторонний блок) - кликните по ГЛАВНОЙ трапеции опоры.")
            )
        )
        (princ "\n[LEP-POLE-DELETE] Отменено.")
    )

    (setq *error* OldError)
    (LEP:PrintFooter)
    (princ)
)


;=====================================================================
; C:LEP-POLE-MOVE
;
; Переносит опору на новую точку - удаляет старую (подпись+откосы+
; блок, LEP:DeletePoleGroup) и вставляет новую тем же способом, что и
; обычная расстановка (LEP:PlacePoleOnRoute), с ТЕМИ ЖЕ типом/статусом,
; прочитанными из XDATA старой опоры ДО удаления - переспрашивать не
; нужно. Добавлено 2026-07-15 по просьбе пользователя - альтернатива
; ручному перетаскиванию блока мышкой, при котором пролёт (LEP-SPAN,
; уже построенный из вершин трассы, а не из положения блоков) мог
; остаться привязан к СТАРОЙ, неверной геометрии, если GEOMCONSTRAINT
; почему-то не удержал связь опоры с трассой (см. историю в README).
;
; ⚠️ Если вставка на новом месте всё же не удастся (редкий случай) -
; старая опора к этому моменту уже удалена, отдельное предупреждение
; в консоль - ставьте новую вручную командой LEP-POLE.
;
; ✅ ФИКС 2026-07-28: ПЕРЕНОС ОПОРЫ БОЛЬШЕ НЕ ОБЕДНЯЕТ ЕЁ.
;
; Раньше переносились только ТИП и СТАТУС - всё остальное молча
; терялось, потому что новая опора создаётся с нуля обычной
; LEP:PlacePoleOnRoute, а та знает лишь про обычную опору на трассе:
;
;   - ключ EQUIP (ПУ/СТП/РЛК/МТП/ЩУ) - опора переставала быть опорой с
;     оборудованием, и это оборудование ПРОПАДАЛО ИЗ ВЕДОМОСТИ
;     (LEP-REPORT считает его именно по EQUIP). Молча, без ошибки;
;   - текст подписи - новая собиралась стандартная, "[статус] оп.
;     [тип]" + класс напряжения. Всё, что было дописано в подпись
;     сверх этого, исчезало: "ПУ", "+ проект. ПУ" (оборудование на
;     существующей опоре), "+ подъём кабеля по опоре" (конец
;     кабельного пролёта), "+ СТП-XX кВА".
;
; Теперь ДО удаления запоминаются EQUIP/EQUIPSTATUS и ПОЛНЫЙ текст
; старой подписи, а после вставки новой опоры возвращаются на место:
;
;   - текст подписи ставится старый ЦЕЛИКОМ (LEP:SetMLeaderText,
;     LEP-UTILS.LSP), а не собирается заново. Так надёжнее: перенос НЕ
;     меняет ни тип, ни статус, ни класс линии - значит старый текст
;     остаётся верным ДО ПОСЛЕДНЕЙ БУКВЫ, и его не нужно пытаться
;     воспроизвести по кускам (а воспроизвести полностью и нельзя -
;     дописанные строки в XDATA не хранятся нигде, они существуют
;     только в самом тексте подписи);
;   - EQUIP/EQUIPSTATUS дописываются в XDATA новой опоры через
;     LEP:AddEquipToExistingPole (LEP-DATA.LSP) - ту самую функцию,
;     которая умеет добавить оборудование, НЕ затирая остальные поля
;     (TYPE/ROUTE/MODEL/STATUS/LABELHANDLE новой опоры).
;
; ⚠️ Если у старой опоры не было LABELHANDLE (опоры, поставленные ДО
; фикса 2026-07-28, см. LEP:AddEquipData) - переносить текст неоткуда,
; подпись останется стандартной, новой. Это не ошибка, а честный предел
; возможного: старый текст в этом случае в чертеже уже не найти.
;=====================================================================

(defun C:LEP-POLE-MOVE (/ Route Ent RouteID PoleType Status ClassLabel VClass NewPoint NewPoleEnt
                          Equip EquipStatus OldLabelHandle OldLabelEnt OldLabelText
                          NewLabelHandle NewLabelEnt OldError)

    (setq OldError *error*)
    (defun *error* (msg)
        (setq *error* OldError)
        (princ (strcat "\nКоманда прервана: " msg))
        (princ)
    )

    (LEP:PrintHeader "Перенос опоры")

    (setq Route (car (entsel "\nВыберите полилинию маршрута (если не видна - включите LEP-ROUTEVIS): ")))

    (if Route
        (progn
            (setq Ent (car (entsel "\nКликните по опоре, которую нужно передвинуть: ")))

            (if (and Ent
                     (= (cdr (assoc 0 (entget Ent))) "INSERT")
                     (= (LEP:GetDataValue Ent "TYPE") "POLE")
                )
                (progn
                    ;; Читаем старые данные ДО удаления - тип/статус
                    ;; переносятся на новую опору без переспроса.
                    (setq RouteID (LEP:GetDataValue Ent "ROUTE"))
                    (setq PoleType (LEP:GetDataValue Ent "MODEL"))
                    (setq Status (LEP:GetDataValue Ent "STATUS"))

                    ;; ✅ 2026-07-28 (см. шапку команды): оборудование и
                    ;; текст подписи - тоже ДО удаления. EQUIP есть не у
                    ;; каждой опоры (у обычной его нет вовсе) - тогда
                    ;; здесь просто nil, и ниже ничего не восстановится.
                    (setq Equip (LEP:GetDataValue Ent "EQUIP"))
                    (setq EquipStatus (LEP:GetDataValue Ent "EQUIPSTATUS"))

                    ;; Текст подписи читаем СЕЙЧАС, пока подпись ещё
                    ;; существует: LEP:DeletePoleGroup ниже сотрёт её
                    ;; вместе с опорой, и после этого взять текст будет
                    ;; неоткуда.
                    (setq OldLabelHandle (LEP:GetDataValue Ent "LABELHANDLE"))
                    (if OldLabelHandle
                        (setq OldLabelEnt (handent OldLabelHandle))
                    )
                    (if OldLabelEnt
                        (setq OldLabelText (LEP:GetMLeaderText OldLabelEnt))
                    )

                    (setq VClass (LEP:GetDataValue Route "VCLASS"))
                    (setq ClassLabel (cdr (assoc VClass *LEP-VoltageClassLabel*)))

                    (setq NewPoint (getpoint "\nНовая точка для опоры: "))

                    (if NewPoint
                        (progn
                            (LEP:DeletePoleGroup Ent)
                            (setq NewPoleEnt (LEP:PlacePoleOnRoute Route RouteID ClassLabel NewPoint PoleType Status VClass))

                            ;; ✅ 2026-07-28 (см. шапку команды): возвращаем
                            ;; новой опоре то, чего LEP:PlacePoleOnRoute про
                            ;; неё не знает - старый текст подписи и данные
                            ;; об оборудовании.
                            (if NewPoleEnt
                                (progn

                                    ;; Текст подписи - старый ЦЕЛИКОМ. Хендл
                                    ;; НОВОЙ подписи берём из XDATA новой
                                    ;; опоры (LEP:AddPoleData его туда уже
                                    ;; записала внутри LEP:PlacePoleOnRoute).
                                    (if OldLabelText
                                        (progn
                                            (setq NewLabelHandle (LEP:GetDataValue NewPoleEnt "LABELHANDLE"))
                                            (if NewLabelHandle
                                                (setq NewLabelEnt (handent NewLabelHandle))
                                            )
                                            (if NewLabelEnt
                                                (LEP:SetMLeaderText NewLabelEnt OldLabelText)
                                            )
                                        )
                                    )

                                    ;; Оборудование - через "дописать, не
                                    ;; затирая остальное" (см. шапку
                                    ;; LEP:AddEquipToExistingPole): обычная
                                    ;; LEP:AddEquipData снесла бы LABELHANDLE
                                    ;; новой опоры, только что записанный.
                                    ;; EquipStatus может быть nil (у опор из
                                    ;; LEP-END его нет) - LEP:SetData тогда
                                    ;; просто не пишет этот ключ, то есть
                                    ;; новая опора получается точь-в-точь
                                    ;; такой же, какой была старая.
                                    (if Equip
                                        (LEP:AddEquipToExistingPole NewPoleEnt Equip EquipStatus)
                                    )
                                )
                            )

                            (if NewPoleEnt
                                (princ "\n[LEP-POLE-MOVE] Опора перенесена.")
                                (princ "\n[LEP-POLE-MOVE] Не удалось вставить опору на новом месте - старая уже удалена, поставьте новую вручную командой LEP-POLE.")
                            )
                        )
                        (princ "\n[LEP-POLE-MOVE] Точка не указана - старая опора НЕ тронута, отменено.")
                    )
                )
                (princ "\n[LEP-POLE-MOVE] Это не опора (возможно, откос или посторонний блок) - кликните по ГЛАВНОЙ трапеции опоры.")
            )
        )
        (princ "\nМаршрут не выбран.")
    )

    (setq *error* OldError)
    (LEP:PrintFooter)
    (princ)
)


;=====================================================================
; LEP:FindNearestRoute
;
; Ищет, к какой трассе на чертеже точка P ближе всего ГЕОМЕТРИЧЕСКИ -
; перебирает ВСЕ полилинии на служебном слое маршрутов
; (*LEP-Layer-Route*), для каждой находит ближайшую точку (тот же
; LEP:FindNearestSegment, что и для одной трассы в обычной LEP-POLE),
; берёт ID трассы с минимальным расстоянием.
;
; !! ВАЖНО - ПОДВОДНЫЙ КАМЕНЬ, см. LEP-README.md !!
; "Ближайшая ГЕОМЕТРИЧЕСКИ" не всегда значит "правильная ПО СМЫСЛУ" -
; если отдельная опора стоит близко к границе между территориями двух
; разных заявителей, автоматика молча привяжет её к не той трассе.
; Вызывающая сторона (C:LEP-POLE-ALONE) печатает в консоль, к какой
; трассе привязалась опора - ПРОВЕРЯЙТЕ этот вывод глазами.
;
; Слой маршрутов обычно ВЫКЛЮЧЕН (LEP-ROUTEVIS) - ssget без явного
; включения слоя не увидел бы на нём ничего. Поэтому здесь слой
; временно включается на время поиска (если был выключен) и
; возвращается в исходное состояние сразу после - той же логикой
; "по знаку цвета в таблице слоёв", что и в C:LEP-ROUTEVIS.
;
; Возвращает: список (ID VClass) - ID трассы и её класс напряжения
; (строки), либо (nil nil), если на чертеже нет ни одной трассы
; вообще. VClass нужен вызывающей стороне (C:LEP-POLE-ALONE) для
; второй строки подписи опоры - у отдельной опоры нет своего явного
; маршрута, поэтому берём класс у той трассы, к которой её же и
; привязали по этой самой функции, чтобы подпись не противоречила
; тому, к чему в итоге ушли данные в ведомость.
;=====================================================================

(defun LEP:FindNearestRoute (P / LayerData WasOff SS i Ent Verts Nearest Dist BestID BestVClass BestDist)

    (setq LayerData (tblsearch "LAYER" *LEP-Layer-Route*))
    (setq WasOff (and LayerData (< (cdr (assoc 62 LayerData)) 0)))

    (if WasOff
        (command "_.-layer" "_On" *LEP-Layer-Route* "")
    )

    (setq SS (ssget "_X" (list '(0 . "LWPOLYLINE") (cons 8 *LEP-Layer-Route*))))
    (setq BestID nil)
    (setq BestVClass nil)
    (setq BestDist nil)

    (if SS
        (progn
            (setq i 0)
            (repeat (sslength SS)
                (setq Ent (ssname SS i))
                (setq Verts (LEP:GetVertices Ent))
                (setq Nearest (LEP:FindNearestSegment Verts P))
                (setq Dist (distance P (cadr Nearest)))

                (if (or (not BestDist) (< Dist BestDist))
                    (progn
                        (setq BestDist Dist)
                        (setq BestID (LEP:GetDataValue Ent "ID"))
                        (setq BestVClass (LEP:GetDataValue Ent "VCLASS"))
                    )
                )

                (setq i (1+ i))
            )
        )
    )

    ;; Возвращаем слой в то состояние, в котором он был - не меняем
    ;; ничего у пользователя незаметно для него.
    (if WasOff
        (command "_.-layer" "_Off" *LEP-Layer-Route* "")
    )

    (list BestID BestVClass)
)


;=====================================================================
; C:LEP-POLE-ALONE - отдельная опора БЕЗ привязки к трассе
;
; То же самое, что обычная LEP-POLE (тип, статус, подпись, данные для
; ведомости) - но БЕЗ проекции на маршрут, БЕЗ вставки вершины, БЕЗ
; GEOMCONSTRAINT. Опора ставится РОВНО туда, куда кликнули, и потом
; свободно двигается по чертежу - никаких привязок (OSMODE тоже не
; трогается, в отличие от обычной LEP-POLE - тут не с чем магнититься
; специально).
;
; Для ведомости опора всё равно привязывается к БЛИЖАЙШЕЙ трассе по
; ID (см. LEP:FindNearestRoute) - см. предупреждение там же про
; геометрическую близость vs смысловую правильность.
;
; Enter без точки - выход из цикла.
;=====================================================================

(defun C:LEP-POLE-ALONE (/ ClickPoint PoleType Status PoleEnt RouteID VClass ClassLabel RouteFound OldError LEP-CatchResult LabelEnt)

    (setq OldError *error*)
    (defun *error* (msg)
        (setq *error* OldError)
        (princ (strcat "\nКоманда прервана: " msg))
        (princ)
    )

    (LEP:PrintHeader "Установка отдельной опоры (без привязки к трассе)")

    (princ "\nКликайте точки установки опор в любом месте чертежа.")
    (princ "\nПривязки (OSMODE) не трогаются - опора ставится ровно туда,")
    (princ "\nкуда кликнули, и свободно двигается потом.")
    (princ "\nEnter без точки - закончить.")

    (setq ClickPoint (getpoint "\nТочка опоры (Enter - закончить): "))

    (while ClickPoint

        (setq LEP-CatchResult
            (vl-catch-all-apply
                '(lambda ()

                    (setq PoleType (LEP:GetPoleType))

                    (if PoleType
                        (progn
                            (setq Status (LEP:GetPoleStatus))

                            ;; Привязка к ближайшей трассе - см. предупреждение
                            ;; в шапке LEP:FindNearestRoute про геометрическую
                            ;; близость vs смысловую правильность. Делаем это
                            ;; ДО подписи (а не после, как раньше) - подписи
                            ;; теперь нужен класс линии, а он берётся именно
                            ;; у той трассы, к которой опору привязали.
                            (setq RouteFound (LEP:FindNearestRoute ClickPoint))
                            (setq RouteID (car RouteFound))
                            (setq VClass (cadr RouteFound))
                            (setq ClassLabel (cdr (assoc VClass *LEP-VoltageClassLabel*)))

                            (if RouteID
                                (princ
                                    (strcat
                                        "\n[LEP-POLE-ALONE] Опора привязана к трассе "
                                        RouteID
                                        " (ближайшая, определена автоматически - проверьте, что это верно)."
                                    )
                                )
                                (progn
                                    (setq RouteID "БЕЗ_ТРАССЫ")
                                    (princ "\n[LEP-POLE-ALONE] На чертеже не найдено ни одной трассы - опора без привязки.")
                                )
                            )

                            ;; Разворот по маршруту здесь не считаем (опора не
                            ;; лежит ни на каком отрезке трассы, "направления"
                            ;; для неё физически нет) - ставим символ без
                            ;; поворота (0.0 радиан).
                            (setq PoleEnt (LEP:InsertPole ClickPoint 0.0 PoleType Status VClass))

                            (if PoleEnt
                                (progn
                                    (setq LabelEnt (LEP:CreatePoleLabel ClickPoint PoleType Status ClassLabel *LEP-Label-Angle-Default*))
                                    ;; Status теперь настоящий - см. фикс в
                                    ;; LEP:AddPoleData (LEP-DATA.LSP). LabelEnt -
                                    ;; хендл подписи в XDATA, см. ФИКС 2026-07-15.
                                    (LEP:AddPoleData PoleEnt RouteID PoleType Status LabelEnt)
                                )
                            )
                        )
                    )
                )
             '())
        )

        (if (vl-catch-all-error-p LEP-CatchResult)
            (princ
                (strcat
                    "\n[LEP-POLE-ALONE] Ошибка на этой точке, пропускаю и продолжаю: "
                    (vl-catch-all-error-message LEP-CatchResult)
                )
            )
        )

        (setq ClickPoint (getpoint "\nТочка опоры (Enter - закончить): "))
    )

    (setq *error* OldError)
    (LEP:PrintFooter)
    (princ)
)


(princ "\nLEP-POLE v1.7 загружен (слой опоры по классу напряжения x статус).")
(princ)