;=====================================================================
;
;   ПРОЕКТ:      LEP
;   ФАЙЛ:        LEP-SPAN.LSP
;   ВЕРСИЯ:      0.2  (испр. Claude)
;
;   ПЕРЕДЕЛАНО ПОЛНОСТЬЮ:
;   Старая версия выделяла ВСЮ полилинию маршрута целиком и красила
;   её в один слой через CHPROP - то есть у одной трассы мог быть
;   только один тип линии на всём протяжении, и именно на этом же
;   месте был краш ("bad argument type: stringp nil").
;
;   Новая логика: пролёт между ДВУМЯ ОПОРАМИ вырезается как
;   ОТДЕЛЬНЫЙ объект-полилиния (копия геометрии этого участка
;   маршрута), со своим слоем/типом линии под ВЛ или КЛ. Исходная
;   полилиния маршрута НЕ трогается и не удаляется - она остаётся
;   "невидимой арматурой", на ней по-прежнему держится привязка опор
;   (GEOMCONSTRAINT из LEP-POLE.LSP).
;
;   ОГРАНИЧЕНИЕ (честно, не прячу): новый объект-пролёт геометрически
;   скопирован с маршрута НА МОМЕНТ создания, но сам по себе не
;   связан через GEOMCONSTRAINT с опорами. Если потом подвинуть
;   опору - основная трасса подстроится, а нарисованный пролёт (с его
;   слоем/подписью) - нет, его нужно будет создать заново командой
;   LEP-SPAN. Это сознательное упрощение ради скорости - если это
;   неудобно, скажите, попробуем другой подход.
;
;   ВЫБОР ПРОЛЁТА: команда просит кликнуть по ДВУМ ТОЧКАМ - рядом с
;   первой опорой и рядом со второй опорой пролёта (а не "щёлкнуть по
;   линии"), потому что между двумя опорами в маршруте может быть
;   лишний изгиб без опоры - "клик по линии" в этом случае был бы
;   неоднозначным.
;
;   Марки проводов/кабелей вынесены в LEP-CONFIG.LSP
;   (*LEP-WireTypes-VL* / *LEP-WireTypes-KL*), как и просили - одно
;   место для расширения списка, а не хардкод в этом файле.
;
;   НАЗНАЧЕНИЕ:
;   Классификация пролётов маршрута (ВЛ/КЛ, марка провода/кабеля),
;   автоматический расчёт длины и подпись.
;
;=====================================================================
 
 
;=====================================================================
; LEP:ChooseFromList
;
; Универсальный выбор одного пункта из списка (car Item) - номером
; в командной строке, с проверкой диапазона и повторным запросом.
; Используется и для типа линии, и для марки провода.
;=====================================================================
 
(defun LEP:ChooseFromList (ItemList PromptText / MenuText i Item Choice Result Valid)
 
    (setq MenuText "")
    (setq i 1)
 
    (foreach Item ItemList
        (setq MenuText (strcat MenuText (itoa i) "-" (car Item) "  "))
        (setq i (1+ i))
    )
 
    (setq Result nil)
    (setq Valid nil)
 
    (while (not Valid)
 
        (initget 6)
        (setq Choice (getint (strcat "\n" MenuText "\n" PromptText ": ")))
 
        (cond
            ((not Choice)
             (setq Valid T)
            )
            ((or (< Choice 1) (> Choice (length ItemList)))
             (princ "\nНет такого номера, попробуйте ещё раз.")
            )
            (t
             (setq Result (nth (1- Choice) ItemList))
             (setq Valid T)
            )
        )
    )
 
    Result
)
 
 
;=====================================================================
; LEP:EnsureLinetypeLoaded
;
; Проверяет, что нужный тип линии загружен в чертёж (например
; "DASHED" для КЛ), и подгружает его из acad.lin, если ещё не
; загружен. "CONTINUOUS" всегда есть по умолчанию, для него ничего
; делать не нужно.
;=====================================================================
 
(defun LEP:EnsureLinetypeLoaded (LtName / OldFiledia)
    (if (and (/= LtName "CONTINUOUS") (not (tblsearch "LTYPE" LtName)))
        (progn
            ;; FILEDIA=1 (по умолчанию) открывает GUI-диалог выбора файла
            ;; вместо текстового промпта на шаге "Select linetype file" -
            ;; тогда "acad.lin" уходит не туда и ломает очередь command.
            (setq OldFiledia (getvar "FILEDIA"))
            (setvar "FILEDIA" 0)
            (command "_.-linetype" "_Load" LtName "acad.lin" "")
            (setvar "FILEDIA" OldFiledia)
        )
    )
)
 
 
;=====================================================================
; LEP:PickPole
;
; Клик ПО САМОМУ БЛОКУ ОПОРЫ (через entsel, не getpoint) - значит,
; работает обычная подсветка объекта при наведении курсора, как в
; любом другом выборе объектов AutoCAD. Возвращает ТОЧНУЮ точку
; вставки блока (без приближения по ближайшей точке).
;
; Проверяет, что выбран именно блок опоры (INSERT) - если кликнули
; мимо или не туда, честно об этом сообщает и возвращает nil, а не
; молча берёт что попало.
;
; Возвращает: точку (x y) или nil.
;=====================================================================
 
(defun LEP:PickPole (PromptText / PickResult Ent EntData Pt)
 
    (setq PickResult (entsel PromptText))
    (setq Pt nil)
 
    (if PickResult
        (progn
            (setq Ent (car PickResult))
            (setq EntData (entget Ent))
 
            (if (= (cdr (assoc 0 EntData)) "INSERT")
                (setq Pt (cdr (assoc 10 EntData))) ; точка вставки блока - без приближений
                (princ "\n[LEP-SPAN] Это не блок опоры - кликните точно по опоре.")
            )
        )
    )
 
    Pt
)
;=====================================================================
; LEP:GetNearestVertexIndex
;
; Находит индекс вершины в списке Verts, ближайшей к точке P.
;=====================================================================
 
(defun LEP:GetNearestVertexIndex (Verts P / i V Dist BestIdx BestDist)
 
    (setq i 0)
    (setq BestDist nil)
    (setq BestIdx 0)
 
    (foreach V Verts
        (setq Dist (distance P V))
        (if (or (not BestDist) (< Dist BestDist))
            (progn
                (setq BestDist Dist)
                (setq BestIdx i)
            )
        )
        (setq i (1+ i))
    )
 
    BestIdx
)
 
 
;=====================================================================
; LEP:SubList
;
; Возвращает подсписок List от индекса From до индекса To включительно.
;=====================================================================
 
(defun LEP:SubList (Lst From To / Result i Item)
    (setq Result nil)
    (setq i 0)
    (foreach Item Lst
        (if (and (>= i From) (<= i To))
            (setq Result (append Result (list Item)))
        )
        (setq i (1+ i))
    )
    Result
)
 
 
;=====================================================================
; LEP:CreateSpanEntity
;
; Создаёт отдельный объект-полилинию для пролёта (список точек
; SubVerts), на нужном слое/типе линии. Возвращает ename нового
; объекта.
;=====================================================================
 
(defun LEP:CreateSpanEntity (SubVerts LayerName LtName / EntList V)
 
    (setq EntList
        (list
            '(0 . "LWPOLYLINE")
            '(100 . "AcDbEntity")
            (cons 8 LayerName)
            (cons 6 LtName)
            '(100 . "AcDbPolyline")
            (cons 90 (length SubVerts))
            '(70 . 0)
        )
    )
 
    (foreach V SubVerts
        (setq EntList (append EntList (list (cons 10 V))))
    )
 
    (entmake EntList)
    (entlast)
)
 
 
;=====================================================================
; LEP:GetSpanLength
;
; Суммарная длина пролёта - сумма расстояний между соседними точками
; списка SubVerts (для прямых участков без дуг).
;=====================================================================
 
(defun LEP:GetSpanLength (SubVerts / i Total)
 
    (setq Total 0.0)
    (setq i 0)
 
    (while (< i (1- (length SubVerts)))
        (setq Total (+ Total (distance (nth i SubVerts) (nth (1+ i) SubVerts))))
        (setq i (1+ i))
    )
 
    Total
)
 
 
;=====================================================================
; LEP:CreateSpanLabel
;
; Подпись-выноска у пролёта: марка провода/кабеля + длина.
;=====================================================================
 
(defun LEP:CreateSpanLabel (SubVerts WireName SpanLen / MidPt TextPt LabelText OldLayer FirstPt LastPt)
 
    (setq OldLayer (getvar "CLAYER"))
    (LEP:SetCurrentLayer *LEP-Layer-Text*)
 
    (setq FirstPt (car SubVerts))
    (setq LastPt (last SubVerts))
 
    (setq MidPt
        (list
            (/ (+ (car FirstPt) (car LastPt)) 2.0)
            (/ (+ (cadr FirstPt) (cadr LastPt)) 2.0)
        )
    )
 
    (setq TextPt
        (list
            (+ (car MidPt) *LEP-LeaderOffset*)
            (+ (cadr MidPt) *LEP-LeaderOffset*)
        )
    )
 
    (setq LabelText
        (strcat WireName ", L=" (rtos SpanLen 2 1) " м")
    )
 
    ;; После двух точек LEADER просит 3 ответа: пусто (закончить линию),
    ;; текст, пусто (закончить текст) - лишний "" тут уводил в подменю
    ;; [Tolerance/Copy/Mtext/Block/None/Undo], а LabelText туда прилетал
    ;; как невалидное ключевое слово.
    (command "_.LEADER" MidPt TextPt "" LabelText "")
 
    (setvar "CLAYER" OldLayer)
)
 
 
;=====================================================================
; C:LEP-SPAN - основная команда
;
; Классификация одного или нескольких пролётов маршрута. Enter без
; точки (на первом клике пары) - выход из цикла.
;=====================================================================
 
(defun C:LEP-SPAN (/ Route Verts P1 P2 Idx1 Idx2 SubVerts LineType WireList WireChoice
                     LayerName LtName SpanEnt SpanLength OldOs OldError LEP-CatchResult)
 
    (setq OldError *error*)
    (defun *error* (msg)
        (if OldOs (setvar "OSMODE" OldOs))
        (setq *error* OldError)
        (princ (strcat "\nКоманда прервана: " msg))
        (princ)
    )
 
    (LEP:PrintHeader "Обработка пролётов и подписи")
 
    (setq Route (car (entsel "\nВыберите полилинию маршрута: ")))
 
    (if Route
        (progn
            (setq Verts (LEP:GetVertexList Route))
 
            (setq OldOs (getvar "OSMODE"))
            (setvar "OSMODE" 0)
 
            (princ "\nДля каждого пролёта кликните ПО БЛОКУ первой опоры,")
            (princ "\nзатем ПО БЛОКУ второй опоры этого пролёта.")
            (princ "\nEnter вместо первой опоры - закончить.")
 
            (setq P1 (LEP:PickPole "\nПервая опора пролёта (Enter - закончить): "))
 
            (while P1
 
                (setq LEP-CatchResult
                    (vl-catch-all-apply
                        '(lambda ()
 
                            (setq P2 (LEP:PickPole "\nВторая опора пролёта: "))
                            (princ (strcat "\n[DEBUG 1] P2 = " (vl-princ-to-string P2)))

                            (if P2
                                (progn
                                    ;; Находим ближайшие вершины маршрута к P1 и P2
                                    (setq Idx1 (LEP:GetNearestVertexIndex Verts P1))
                                    (setq Idx2 (LEP:GetNearestVertexIndex Verts P2))
                                    (princ (strcat "\n[DEBUG 2] Idx1=" (itoa Idx1) " Idx2=" (itoa Idx2)))

                                    ;; Берём подсписок вершин между ними (по возрастанию индекса)
                                    (if (> Idx1 Idx2)
                                        (progn (setq Idx1 (LEP:GetNearestVertexIndex Verts P2))
                                               (setq Idx2 (LEP:GetNearestVertexIndex Verts P1)))
                                    )
                                    (setq SubVerts
                                        (LEP:SubList Verts Idx1 Idx2)
                                    )
                                    (princ (strcat "\n[DEBUG 3] SubVerts len=" (itoa (length SubVerts))))

                                    (if (< (length SubVerts) 2)
                                        (princ "\n[LEP-SPAN] Между этими точками нет отдельного участка маршрута - пропускаю.")
                                        (progn
                                            (princ "\n[DEBUG 4] Перед ChooseFromList (тип прокладки)")
                                            ;; Тип прокладки
                                            (setq LineType
                                                (LEP:ChooseFromList
                                                    (list (cons "ВЛ (воздух)" "VL") (cons "КЛ (земля)" "KL"))
                                                    "Тип прокладки"
                                                )
                                            )
                                            (princ (strcat "\n[DEBUG 5] LineType = " (vl-princ-to-string LineType)))

                                            (if LineType
                                                (progn
                                                    (if (= (cdr LineType) "VL")
                                                        (progn
                                                            (setq WireList *LEP-WireTypes-VL*)
                                                            (setq LayerName *LEP-Layer-Proj-VL*)
                                                            (setq LtName "CONTINUOUS")
                                                        )
                                                        (progn
                                                            (setq WireList *LEP-WireTypes-KL*)
                                                            (setq LayerName *LEP-Layer-Proj-KL*)
                                                            (setq LtName "DASHED")
                                                        )
                                                    )
                                                    (princ (strcat "\n[DEBUG 6] LtName=" LtName " LayerName=" LayerName))

                                                    (LEP:EnsureLinetypeLoaded LtName)
                                                    (princ "\n[DEBUG 7] После EnsureLinetypeLoaded")

                                                    ;; Марка провода/кабеля - список из CONFIG
                                                    (setq WireChoice (LEP:ChooseFromList WireList "Марка провода/кабеля"))
                                                    (princ (strcat "\n[DEBUG 8] WireChoice = " (vl-princ-to-string WireChoice)))

                                                    (if WireChoice
                                                        (progn
                                                            (setq SpanEnt (LEP:CreateSpanEntity SubVerts LayerName LtName))
                                                            (setq SpanLength (LEP:GetSpanLength SubVerts))
                                                            (princ (strcat "\n[DEBUG 9] SpanEnt=" (vl-princ-to-string SpanEnt) " Length=" (rtos SpanLength 2 3)))

                                                            ;; Данные для ведомости: марка, сечение, точная длина
                                                            (LEP:SetData SpanEnt
                                                                (list
                                                                    (cons "TYPE" "SPAN")
                                                                    (cons "WIRE" (car WireChoice))
                                                                    (cons "SECTION" (cdr WireChoice))
                                                                    (cons "LENGTH" (rtos SpanLength 2 3))
                                                                )
                                                            )
                                                            (princ "\n[DEBUG 10] После SetData, перед CreateSpanLabel")

                                                            (LEP:CreateSpanLabel SubVerts (car WireChoice) SpanLength)
                                                            (princ "\n[DEBUG 11] После CreateSpanLabel - пролёт готов")
                                                        )
                                                    )
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
                            "\n[LEP-SPAN] Ошибка на этом пролёте, пропускаю и продолжаю: "
                            (vl-catch-all-error-message LEP-CatchResult)
                        )
                    )
                )
 
                (setq P1 (LEP:PickPole "\nПервая опора пролёта (Enter - закончить): "))
            )
 
            (setvar "OSMODE" OldOs)
        )
        (princ "\nМаршрут не выбран.")
    )
 
    (setq *error* OldError)
    (LEP:PrintFooter)
    (princ)
)
 
 
(princ "\nLEP-SPAN v0.2 загружен (пролёты вырезаются отдельными объектами, без CHPROP).")
(princ)