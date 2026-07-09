;=====================================================================
;
;   ПРОЕКТ:      LEP
;   ФАЙЛ:        LEP-POLE.LSP
;   ВЕРСИЯ:      0.4  (испр. Claude)
;
;   ИСПРАВЛЕНО/ПЕРЕДЕЛАНО В ЭТОЙ ВЕРСИИ:
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
 
 
;=====================================================================
; LEP:GetVertexList
;
; Возвращает список вершин полилинии (список точек (x y)), в порядке
; их следования в объекте.
;=====================================================================
 
(defun LEP:GetVertexList (Ent / EList Item Result)
 
    (setq EList (entget Ent))
    (setq Result nil)
 
    (foreach Item EList
        (if (= (car Item) 10)
            (setq Result (append Result (list (cdr Item))))
        )
    )
 
    Result
)
 
 
;=====================================================================
; LEP:FindNearestSegment
;
; Ищет, к какому отрезку маршрута ближе всего кликнутая точка.
;
; Вход:
;   Verts - список вершин (результат LEP:GetVertexList)
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
; Вход:
;   RouteEnt   - ename полилинии маршрута
;   ClickPoint - точка, которую кликнул пользователь
;
; Выход: точная точка новой вершины (x y) - именно туда нужно ставить
; блок опоры.
;=====================================================================
 
(defun LEP:InsertVertexOnRoute (RouteEnt ClickPoint / Verts Found Idx NewPt NewVerts i V NewEList Item VertexInserted)
 
    (setq Verts (LEP:GetVertexList RouteEnt))
    (setq Found (LEP:FindNearestSegment Verts ClickPoint))
    (setq Idx (car Found))
    (setq NewPt (cadr Found))
 
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
 
    NewPt
)
 
 
;=====================================================================
; LEP:GetPoleType-CmdLine
;
; Запасной способ выбора типа опоры - через командную строку,
; номером. Используется, если DCL-диалог недоступен/не открылся.
;
; Возвращает: строку с типом опоры, либо nil при отмене (Esc).
;=====================================================================
 
(defun LEP:GetPoleType-CmdLine (/ MenuText i Item Choice Result Valid)
 
    (setq MenuText "")
    (setq i 1)
 
    (foreach Item *LEP-PoleTypes*
        (setq MenuText (strcat MenuText (itoa i) "-" (car Item) "  "))
        (setq i (1+ i))
    )
 
    (setq Result nil)
    (setq Valid nil)
 
    (while (not Valid)
 
        (initget 6) ; запрещаем 0 и отрицательные (Esc/пусто - отмена)
        (setq Choice (getint (strcat "\n" MenuText "\nНомер опоры: ")))
 
        (cond
            ((not Choice)
             (setq Valid T)
            )
            ((or (< Choice 1) (> Choice (length *LEP-PoleTypes*)))
             (princ "\nНет такого номера в списке, попробуйте ещё раз.")
            )
            (t
             (setq Result (car (nth (1- Choice) *LEP-PoleTypes*)))
             (setq Valid T)
            )
        )
    )
 
    Result
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
; настройки *LEP-UseDCL* в LEP-CONFIG.LSP (по умолчанию - диалог).
;=====================================================================
 
(defun LEP:GetPoleType ()
    (if (and (boundp '*LEP-UseDCL*) (not *LEP-UseDCL*))
        (LEP:GetPoleType-CmdLine)
        (LEP:GetPoleType-DCL)
    )
)
 
 
;=====================================================================
; LEP:GetPoleStatus
;
; Запрашивает статус опоры: Проект или Существующая.
; Возвращает "PROJECT" или "EXIST".
;=====================================================================
 
(defun LEP:GetPoleStatus (/ Choice)
 
    (initget "Проект Сущ")
    (setq Choice
        (getkword "\nСтатус опоры [Проект/Сущ] <Проект>: ")
    )
 
    (if (or (not Choice) (= Choice "Проект"))
        "PROJECT"
        "EXIST"
    )
)
 
 
;=====================================================================
; LEP:SetBlockAttribute
;
; Записывает значение в атрибут уже вставленного блока.
; Работает БЕЗ ActiveX (только entnext/entget/entmod).
;=====================================================================
 
(defun LEP:SetBlockAttribute (BlockEnt Tag NewValue / SubEnt SubData Found)
 
    (setq Found nil)
    (setq SubEnt (entnext BlockEnt))
 
    (while (and SubEnt (not Found))
 
        (setq SubData (entget SubEnt))
 
        (cond
 
            ((= (cdr (assoc 0 SubData)) "SEQEND")
                (setq SubEnt nil)
            )
 
            ((and (= (cdr (assoc 0 SubData)) "ATTRIB")
                  (= (cdr (assoc 2 SubData)) Tag))
                (entmod (subst (cons 1 NewValue) (assoc 1 SubData) SubData))
                (entupd SubEnt)
                (setq Found T)
            )
 
            (t
                (setq SubEnt (entnext SubEnt))
            )
 
        )
 
    )
 
    Found
)
 
 
;=====================================================================
; LEP:InsertPole
;
; Вставка блока опоры (всегда один и тот же блок *LEP-Block-Pole*)
; в указанную точку, с записью типа в атрибут и переключением слоя
; по статусу.
;=====================================================================
 
(defun LEP:InsertPole (Point PoleType Status / OldLayer OldAttreq Ent TargetLayer)
 
    (setq OldLayer (getvar "CLAYER"))
 
    (if (= Status "EXIST")
        (setq TargetLayer *LEP-Layer-Exist-Pole*)
        (setq TargetLayer *LEP-Layer-Proj-Pole*)
    )
    (LEP:SetCurrentLayer TargetLayer)
 
    (setq OldAttreq (getvar "ATTREQ"))
    (setvar "ATTREQ" 0)
 
    (command "_.-INSERT" *LEP-Block-Pole* Point 1 1 0)
 
    (setvar "ATTREQ" OldAttreq)
 
    (setq Ent (entlast))
 
    (if (not (LEP:SetBlockAttribute Ent *LEP-Block-Pole-AttTag* PoleType))
        (princ
            (strcat
                "\n[LEP-POLE] ВНИМАНИЕ: не найден атрибут с тегом \""
                *LEP-Block-Pole-AttTag*
                "\" в блоке \"" *LEP-Block-Pole* "\"."
            )
        )
    )
 
    (setvar "CLAYER" OldLayer)
 
    Ent
)
 
 
;=====================================================================
; LEP:CreatePoleLabel
;
; Подпись-выноска (LEADER) рядом с опорой.
;
; ВАЖНО (см. шапку файла): сейчас в подписи только статус и тип
; опоры. Класс линии/напряжение сюда пока не добавлены - это
; открытый вопрос, см. LEP-README.md.
;=====================================================================
 
(defun LEP:CreatePoleLabel (Point PoleType Status / StatusText LabelText TextPoint OldLayer)
 
    (setq OldLayer (getvar "CLAYER"))
    (LEP:SetCurrentLayer *LEP-Layer-Text*)
 
    (if (= Status "EXIST")
        (setq StatusText "Сущ.")
        (setq StatusText "Проект.")
    )
 
    (setq LabelText (strcat StatusText " оп. " PoleType))
 
    ;; Точка для текста - со смещением от опоры, чтобы не накладывалась
    ;; на сам блок. *LEP-LeaderOffset* - настройка в LEP-CONFIG.LSP
    ;; (если такой переменной ещё нет - добавьте:
    ;;   (setq *LEP-LeaderOffset* 5.0)   ; метров, после калибровки
    ;; ).
    (setq TextPoint
        (list
            (+ (car Point) *LEP-LeaderOffset*)
            (+ (cadr Point) *LEP-LeaderOffset*)
        )
    )
 
    (command "_.LEADER" Point TextPoint "" "" LabelText "")
 
    (setvar "CLAYER" OldLayer)
)
 
 
;=====================================================================
; C:LEP-POLE - основная команда
;
; РУЧНАЯ расстановка опор в цикле. Каждый клик - это:
; проекция на линию -> новая вершина -> блок опоры -> тип -> статус
; -> связь с линией -> подпись -> данные для ведомости.
; Enter без точки - выход из цикла.
;=====================================================================
 
(defun C:LEP-POLE (/ Route RouteID OldOs OldError ClickPoint NewVertex PoleType Status PoleEnt)
 
    (setq OldError *error*)
    (defun *error* (msg)
        (if OldOs (setvar "OSMODE" OldOs))
        (setq *error* OldError)
        (princ (strcat "\nКоманда прервана: " msg))
        (princ)
    )
 
    (LEP:PrintHeader "Установка опор (ручная)")
 
    (setq Route (car (entsel "\nВыберите полилинию маршрута: ")))
 
    (if Route
        (progn
 
            (setq RouteID (LEP:GetDataValue Route "ID"))
            (if (not RouteID) (setq RouteID "LEP_ROUTE_UNKNOWN"))
 
            (setq OldOs (getvar "OSMODE"))
            (setvar "OSMODE" 0)
 
            (princ "\nКликайте точки установки опор рядом с трассой.")
            (princ "\nEnter без точки - закончить.")
 
            (setq ClickPoint (getpoint "\nТочка опоры (Enter - закончить): "))
 
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
 
                            ;; 1. Находим ближайшую точку на линии и
                            ;;    вставляем туда новую вершину полилинии.
                            (setq NewVertex (LEP:InsertVertexOnRoute Route ClickPoint))
 
                            ;; 2. Спрашиваем тип и статус опоры.
                            (setq PoleType (LEP:GetPoleType))
 
                            (if PoleType
                                (progn
                                    (setq Status (LEP:GetPoleStatus))
 
                                    ;; 3. Вставляем блок опоры в новую вершину.
                                    (setq PoleEnt (LEP:InsertPole NewVertex PoleType Status))
 
                                    (if PoleEnt
                                        (progn
                                            ;; 4. Привязываем опору к вершине маршрута.
                                            (command "_.GEOMCONSTRAINT" "_COincident" PoleEnt NewVertex Route NewVertex "")
 
                                            ;; 5. Подпись-выноска.
                                            (LEP:CreatePoleLabel NewVertex PoleType Status)
 
                                            ;; 6. Данные для ведомости.
                                            (LEP:AddPoleData PoleEnt RouteID PoleType)
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
 
                (setq ClickPoint (getpoint "\nТочка опоры (Enter - закончить): "))
            )
 
            (setvar "OSMODE" OldOs)
        )
        (princ "\nМаршрут не выбран.")
    )
 
    (setq *error* OldError)
    (LEP:PrintFooter)
    (princ)
)
 
 
(princ "\nLEP-POLE v0.4 загружен (ручная расстановка опор с врезкой вершины в линию).")
(princ)