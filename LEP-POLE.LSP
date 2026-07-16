;=====================================================================
;
;   ПРОЕКТ:      LEP
;   ФАЙЛ:        LEP-POLE.LSP
;   ВЕРСИЯ:      1.2  (LEP:PromptNextPolePoint - расстояние от
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

(defun LEP:InsertPole (Point Rotation PoleType Status / OldLayer Ent TargetLayer)

    (setq OldLayer (getvar "CLAYER"))

    (if (= Status "EXIST")
        (setq TargetLayer *LEP-Layer-Exist-Pole*)
        (setq TargetLayer *LEP-Layer-Proj-Pole*)
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

(defun LEP:CreatePoleLabel (Point PoleType Status ClassLabel OffsetAngle / StatusText LabelText TextPoint OldLayer)

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

    ;; Фон под текстом - свойство КАЖДОЙ выноски отдельно, не стиля
    ;; (см. LEP-CONFIG.LSP, раздел "ФОНОВАЯ МАСКА ТЕКСТА ВЫНОСОК").
    (LEP:SetMLeaderBackgroundMask (entlast))

    (setvar "CLAYER" OldLayer)
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
;   2. Иначе - СНАЧАЛА спрашивает расстояние ЧИСЛОМ (getreal - клик
;      мышкой по обычному поведению AutoLISP тут просто игнорируется,
;      ждёт клавиатуру). Если ввели положительное число - точка
;      считается вдоль трассы через LEP:GetPointAtDistance
;      (LEP-POLYLINE.LSP), в направлении Forward. Если Enter (не
;      ввели число) - обычный клик мышкой, НО с базовой точкой
;      PrevPoint - тогда AutoCAD САМ рисует резинку от предыдущей
;      опоры до курсора и (если у пользователя включён Dynamic Input)
;      сам показывает расстояние/угол рядом с курсором, бесплатно, без
;      всякой дополнительной графики с нашей стороны.
;
; ⚠️ НЕ проверено вживую, что getreal гарантированно игнорирует клик
; мышкой (а не пытается интерпретировать его как-то ещё) - это
; стандартное, задокументированное поведение AutoLISP, но именно ЭТОТ
; частный случай в этом проекте живьём не тестировался - проверить при
; первом реальном использовании.
;
; Forward (T/nil) - направление вдоль трассы, определяется ОДИН РАЗ в
; C:LEP-POLE после первой опоры (по тому, к какой вершине маршрута она
; ближе - тот же принцип, что и ФИКС направления МТП в LEP-END.LSP),
; сюда просто передаётся готовым.
;=====================================================================

(defun LEP:PromptNextPolePoint (Route PrevPoint Forward / DistInput RouteVerts PrevIdx)

    (if (not PrevPoint)

        (getpoint "\nТочка опоры (Enter - закончить): ")

        (progn
            (initget 0)
            (setq DistInput
                (getreal "\nРасстояние от предыдущей опоры, м (Enter - указать точку мышкой): ")
            )

            (cond
                ((not DistInput)
                 (getpoint PrevPoint "\nТочка опоры (Enter - закончить): ")
                )
                ((<= DistInput 0)
                 (princ "\n[LEP-POLE] Расстояние должно быть положительным - укажите точку мышкой.")
                 (getpoint PrevPoint "\nТочка опоры (Enter - закончить): ")
                )
                (t
                 (setq RouteVerts (LEP:GetVertices Route))
                 (setq PrevIdx (LEP:GetNearestVertexIndex RouteVerts PrevPoint))
                 (LEP:GetPointAtDistance RouteVerts PrevIdx DistInput Forward)
                )
            )
        )
    )
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
(defun C:LEP-POLE (/ Route RouteID VClass ClassLabel OldOs OldError ClickPoint InsertResult NewVertex Rotation PoleType Status PoleEnt LEP-CatchResult PrevPoint Forward ForwardKnown RouteVerts)
 
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
            (princ "\nНачиная со 2-й опоры можно ввести расстояние от предыдущей числом.")

            (setq ClickPoint (LEP:PromptNextPolePoint Route PrevPoint Forward))

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

                                    ;; 2. Находим ближайшую точку на линии и
                                    ;;    вставляем туда новую вершину полилинии.
                                    ;;    Заодно получаем концы отрезка маршрута
                                    ;;    под ней - нужны для разворота символа
                                    ;;    опоры по направлению трассы.
                                    (setq InsertResult (LEP:InsertVertexOnRoute Route ClickPoint))
                                    (setq NewVertex (car InsertResult))
                                    (setq Rotation (LEP:GetPoleRotation (cadr InsertResult) (caddr InsertResult)))

                                    ;; 3. Вставляем символ опоры (1/2/3
                                    ;;    трапеции по типу) в новую вершину.
                                    (setq PoleEnt (LEP:InsertPole NewVertex Rotation PoleType Status))

                                    (if PoleEnt
                                        (progn
                                            ;; 4. Привязываем ГЛАВНУЮ трапецию
                                            ;;    к вершине маршрута (откосы,
                                            ;;    если есть, не привязаны -
                                            ;;    чисто визуальная деталь).
                                            (command "_.GEOMCONSTRAINT" "_COincident" PoleEnt NewVertex Route NewVertex "")

                                            ;; ⚠️ Страховка (2026-07-10): если
                                            ;; GEOMCONSTRAINT всё же не смог
                                            ;; наложить связь (диалог "Geometric
                                            ;; Constraints" в AutoCAD) - команда
                                            ;; сама по себе НЕ завершается, а
                                            ;; остаётся ждать повторного выбора
                                            ;; объекта ("Press OK to reselect...").
                                            ;; Пустой (command) - это Escape в
                                            ;; AutoLISP, гарантированно закрывает
                                            ;; любую всё ещё активную команду,
                                            ;; чтобы один неудачный констрейнт не
                                            ;; портил весь остальной цикл (см.
                                            ;; переписку с пользователем про
                                            ;; "Select object: _.GEOMCONSTRAINT").
                                            (command)

                                            ;; 5. Подпись-выноска (2 строки).
                                            (LEP:CreatePoleLabel NewVertex PoleType Status ClassLabel *LEP-Label-Angle-Default*)

                                            ;; 6. Данные для ведомости (Status
                                            ;;    теперь настоящий - см. фикс в
                                            ;;    LEP:AddPoleData, LEP-DATA.LSP).
                                            (LEP:AddPoleData PoleEnt RouteID PoleType Status)

                                            ;; 7. Запоминаем точку - от неё
                                            ;;    будет отсчитываться расстояние
                                            ;;    для следующей опоры (см.
                                            ;;    LEP:PromptNextPolePoint).
                                            ;;    Direction (Forward) - только
                                            ;;    ОДИН РАЗ, после ПЕРВОЙ опоры:
                                            ;;    к какой вершине маршрута она
                                            ;;    ближе - в ТУ сторону НЕ идём,
                                            ;;    идём от неё (тот же принцип,
                                            ;;    что и фикс направления МТП в
                                            ;;    LEP-END.LSP). ⚠️ Флаг
                                            ;;    ForwardKnown ОТДЕЛЬНО от
                                            ;;    самого Forward - Forward=nil
                                            ;;    это ЗАКОННОЕ значение
                                            ;;    ("назад"), не "ещё не
                                            ;;    посчитано", иначе направление
                                            ;;    молча пересчитывалось бы на
                                            ;;    каждой опоре заново.
                                            (setq PrevPoint NewVertex)
                                            (if (not ForwardKnown)
                                                (progn
                                                    (setq RouteVerts (LEP:GetVertices Route))
                                                    (setq Forward
                                                        (< (distance PrevPoint (car RouteVerts))
                                                           (distance PrevPoint (last RouteVerts))
                                                        )
                                                    )
                                                    (setq ForwardKnown T)
                                                )
                                            )
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
                            "\n[LEP-POLE] Ошибка на этой точке, пропускаю и продолжаю: "
                            (vl-catch-all-error-message LEP-CatchResult)
                        )
                    )
                )

                (setq ClickPoint (LEP:PromptNextPolePoint Route PrevPoint Forward))
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

(defun C:LEP-POLE-ALONE (/ ClickPoint PoleType Status PoleEnt RouteID VClass ClassLabel RouteFound OldError LEP-CatchResult)

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
                            (setq PoleEnt (LEP:InsertPole ClickPoint 0.0 PoleType Status))

                            (if PoleEnt
                                (progn
                                    (LEP:CreatePoleLabel ClickPoint PoleType Status ClassLabel *LEP-Label-Angle-Default*)
                                    ;; Status теперь настоящий - см. фикс в
                                    ;; LEP:AddPoleData (LEP-DATA.LSP).
                                    (LEP:AddPoleData PoleEnt RouteID PoleType Status)
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


(princ "\nLEP-POLE v0.9 загружен (аудит: порядок вопросов, честный STATUS).")
(princ)