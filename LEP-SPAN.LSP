;=====================================================================
;
;   ПРОЕКТ:      LEP
;   ФАЙЛ:        LEP-SPAN.LSP
;   ВЕРСИЯ:      0.6  (LEP:CreateSpanLabel: LEADER -> MLEADER, Claude, 2026-07-15)
;                0.5  (LEP:PickPole не принимает откосы/чужие блоки -
;                аудит Claude Fable, 2026-07-11)
;
;   ДОБАВЛЕНО В ЭТОЙ ВЕРСИИ:
;   Список марок ВЛ-провода теперь зависит от класса напряжения
;   МАРШРУТА (VCLASS в XDATA, см. LEP-ROUTE.LSP) - СИП-3
;   (*LEP-WireTypes-VL-10*) для 10кВ, СИП-2 (*LEP-WireTypes-VL-04*)
;   для 0,4кВ. Раньше был один общий список *LEP-WireTypes-VL* на все
;   случаи - физически СИП-2 и СИП-3 для разных классов напряжения не
;   взаимозаменяемы, старый список мог предложить не тот провод.
;
;   РАНЕЕ ДОБАВЛЕНО:
;   Расстояние между опорами (по прямой) и реальная длина провода/
;   кабеля, которую нужно закупить - теперь РАЗНЫЕ величины:
;     - LEP:GetRealLength - ВЛ получает запас на провис в процентах
;       (*LEP-Sag-VL*), КЛ - фиксированный запас на подъём на опору
;       (*LEP-KL-Reserve*), обе настройки в LEP-CONFIG.LSP. Результат
;       округляется ВВЕРХ до целого метра (для закупки материала) -
;       именно эта величина теперь и в подписи пролёта, и в XDATA
;       LENGTH (а значит и в ведомости LEP-REPORT).
;     - LEP:CreateSpanDimension - отдельная размерная линия (стрелками,
;       слой LEP-DIM) с ПРЯМЫМ расстоянием между опорами, округлённым
;       по обычным правилам математики (LEP:RoundNearest) - это уже
;       не про материал, а про геометрию, для наглядности на чертеже.
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
 
 
;; LEP:ChooseFromList перенесена в LEP-UTILS.LSP (используется и
;; здесь, и в LEP-POLE.LSP для списка типов опор - раньше была тут
;; в одном экземпляре, теперь общая).



;=====================================================================
; LEP:EnsureLinetypeLoaded
;
; Проверяет, что нужный тип линии загружен в чертёж (например
; "LEP_CABLE" для КЛ), и подгружает его из файла LtFile, если ещё не
; загружен. LtFile ищется через findfile (Support Path/папка с
; модулями), путь не хардкодится - см. правило проекта в CLAUDE.md.
; "CONTINUOUS" всегда есть по умолчанию, для него ничего делать не
; нужно.
;=====================================================================

(defun LEP:EnsureLinetypeLoaded (LtName LtFile / OldFiledia FullPath)
    (if (and (/= LtName "CONTINUOUS") (not (tblsearch "LTYPE" LtName)))
        (progn
            ;; FILEDIA=1 (по умолчанию) открывает GUI-диалог выбора файла
            ;; вместо текстового промпта на шаге "Select linetype file" -
            ;; тогда LtFile уходит не туда и ломает очередь command.
            (setq OldFiledia (getvar "FILEDIA"))
            (setvar "FILEDIA" 0)

            (setq FullPath (findfile LtFile))
            (if (not FullPath)
                (progn
                    (princ (strcat "\n[LEP-SPAN] Не найден файл типов линий: " LtFile " - положите его в папку с модулями LEP."))
                    (setq FullPath LtFile)
                )
            )

            (command "_.-linetype" "_Load" LtName FullPath "")
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
; ⚠️ ФИКС 2026-07-11 (аудит): раньше проверялся только тип сущности
; (INSERT) - под проверку проходил ЛЮБОЙ блок, включая ОТКОС опоры
; (та же трапеция LEP-POLE-SYM, стоит в 2 м сбоку от трассы) и вообще
; посторонние блоки из подложки. Клик по откосу давал точку в 2 м от
; настоящей опоры - размерная линия и границы пролёта тихо считались
; от неверной точки. Теперь дополнительно проверяется XDATA: у
; ГЛАВНОЙ трапеции есть ключ TYPE=POLE (его пишет LEP:AddPoleData/
; LEP:AddEquipData), у откосов XDATA нет вообще (см.
; LEP:InsertPoleGroup - данные получает только главная) - это готовый
; естественный фильтр, отличающий настоящую опору от её откоса и от
; чужих блоков.
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

            (if (and (= (cdr (assoc 0 EntData)) "INSERT")
                     (= (LEP:GetDataValue Ent "TYPE") "POLE")
                )
                (setq Pt (cdr (assoc 10 EntData))) ; точка вставки блока - без приближений
                (princ "\n[LEP-SPAN] Это не опора (возможно, откос или посторонний блок) - кликните по ГЛАВНОЙ трапеции опоры.")
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
; списка SubVerts (для прямых участков без дуг). Это геометрический
; путь ВДОЛЬ трассы - используется как основа для расчёта реальной
; длины материала (LEP:GetRealLength), НЕ то же самое, что прямое
; расстояние между самими опорами (см. LEP:CreateSpanDimension).
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
; LEP:GetRealLength
;
; Реальная длина провода/кабеля с запасом - ОТДЕЛЬНАЯ величина от
; расстояния между опорами. Разные формулы для ВЛ и КЛ (обе настройки
; в LEP-CONFIG.LSP):
;   ВЛ - провод провисает между опорами (стрела провеса), нужен запас
;        в процентах от длины (*LEP-Sag-VL*, по умолчанию 2%);
;   КЛ - кабель в земле НЕ провисает, но с каждой стороны пролёта ему
;        нужно подняться от земли на опору - фиксированный запас в
;        метрах на весь пролёт (*LEP-KL-Reserve*, по умолчанию 6 м).
; Результат ВСЕГДА округляется ВВЕРХ до целого метра (LEP:RoundUp,
; LEP-UTILS.LSP) - для закупки материала округлять вниз нельзя, не
; хватит на монтаже.
;
; Запас на муфты/разделку кабеля СОЗНАТЕЛЬНО не считается - остаётся
; на усмотрение проектировщика при подготовке настоящей сметы, эта
; программа даёт только черновую прикидку.
;
; TypeCode - "VL" или "KL" (cdr от LineType - см. C:LEP-SPAN).
;=====================================================================

(defun LEP:GetRealLength (TypeCode SpanLength)
    (if (= TypeCode "VL")
        (LEP:RoundUp (* SpanLength (+ 1.0 (/ *LEP-Sag-VL* 100.0))))
        (LEP:RoundUp (+ SpanLength *LEP-KL-Reserve*))
    )
)


;=====================================================================
; LEP:CreateSpanDimension
;
; Линейный размер (стрелками, LEP-DIM слой) между двумя опорами
; пролёта - ПРЯМОЕ расстояние P1-P2 (не путь вдоль трассы, а "по
; линейке от опоры до опоры", как в классическом черчении). Это
; ОТДЕЛЬНАЯ величина от реальной длины провода/кабеля с запасом
; (LEP:GetRealLength) - показывает геометрию, а не сколько материала
; нужно закупить.
;
; Размерная линия сдвинута от прямой P1-P2 ПЕРПЕНДИКУЛЯРНО на
; *LEP-LeaderOffset*, чтобы не накладываться на сам нарисованный
; пролёт (перпендикуляр к направлению P1->P2, а не диагональный
; сдвиг, как у текстовых подписей - для размерной линии так привычнее
; и аккуратнее смотрится).
;
; Текст размера ПЕРЕОПРЕДЕЛЁН вручную через опцию "_Text" у DIMALIGNED
; на заранее округлённое DimDistance (целое число метров по обычным
; правилам округления - см. LEP:RoundNearest в C:LEP-SPAN) - без
; этого DIMALIGNED сам измерил бы точное расстояние с дробной частью,
; а нам нужно именно круглое число.
;
; DIMALIGNED вместо DIMLINEAR (замена от 2026-07-10, по просьбе
; пользователя): DIMLINEAR всегда рисует размер строго горизонтально
; или вертикально, а пролёт между опорами может идти под любым углом -
; из-за этого размерная линия визуально "отрывалась" от самого пролёта.
; DIMALIGNED рисует размерную линию ПАРАЛЛЕЛЬНО отрезку P1-P2, что для
; пролёта ЛЭП геометрически правильнее. Порядок аргументов у command
; для DIMALIGNED с опцией "_Text" повторяет DIMLINEAR - обе команды
; из одного семейства "линейных" размеров AutoCAD с одинаковой
; последовательностью запросов (первая точка выноски, вторая точка
; выноски, положение размерной линии/[Mtext/Text/Angle]), поэтому
; порядок аргументов ниже не менялся. Ориентация текста подписи
; (сейчас поворачивается вместе с размерной линией) пока не трогаем -
; ждём, как это будет смотреться на реальном чертеже.
;=====================================================================

(defun LEP:CreateSpanDimension (P1 P2 DimDistance / OldLayer Dx Dy Len Nx Ny MidX MidY DimLocPt DimText)

    (setq OldLayer (getvar "CLAYER"))
    (LEP:SetCurrentLayer *LEP-Layer-Dim*)

    (setq Dx (- (car P2) (car P1)))
    (setq Dy (- (cadr P2) (cadr P1)))
    (setq Len (distance P1 P2))

    (if (> Len 1e-9)
        (progn
            ;; Единичный перпендикуляр к направлению P1->P2 - в какую
            ;; сторону сдвинуть размерную линию от самого пролёта.
            (setq Nx (/ (- Dy) Len))
            (setq Ny (/ Dx Len))

            (setq MidX (/ (+ (car P1) (car P2)) 2.0))
            (setq MidY (/ (+ (cadr P1) (cadr P2)) 2.0))

            (setq DimLocPt
                (list
                    (+ MidX (* Nx *LEP-LeaderOffset*))
                    (+ MidY (* Ny *LEP-LeaderOffset*))
                )
            )

            (setq DimText (strcat (itoa DimDistance) " м"))

            (command "_.DIMALIGNED" P1 P2 "_Text" DimText DimLocPt)
        )
    )

    (setvar "CLAYER" OldLayer)
)


;=====================================================================
; LEP:CreateSpanLabel
;
; Подпись-выноска у пролёта: статус + марка провода/кабеля + длина.
; Формат статуса тот же, что у опор (LEP:CreatePoleLabel) - "Проект."
; / "Сущ." - для единообразия подписей на чертеже.
;
; SpanLen - теперь РЕАЛЬНАЯ длина материала с запасом (см.
; LEP:GetRealLength), уже округлённая ВВЕРХ до целого метра, а не
; сырое геометрическое расстояние, как раньше - поэтому выводится
; просто целым числом (itoa), без десятичного разряда.
;=====================================================================

(defun LEP:CreateSpanLabel (SubVerts WireName SpanLen Status / MidPt TextPt LabelText OldLayer FirstPt LastPt StatusText)

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
 
    (if (= Status "EXIST")
        (setq StatusText "Сущ.")
        (setq StatusText "Проект.")
    )

    (setq LabelText
        (strcat StatusText " " WireName ", L=" (itoa SpanLen) " м")
    )
 
    ;; МИГРАЦИЯ 2026-07-15: LEADER -> MLEADER (см. LEP-CONFIG.LSP,
    ;; раздел "СТИЛЬ ВЫНОСОК MLEADER"). Вызов проще, чем у LEADER -
    ;; просто две точки и текст, без "пусто"-ответов на промежуточные
    ;; промпты.
    (command "_.MLEADER" MidPt TextPt LabelText)
 
    (setvar "CLAYER" OldLayer)
)
 
 
;=====================================================================
; C:LEP-SPAN - основная команда
;
; Классификация одного или нескольких пролётов маршрута. Enter без
; точки (на первом клике пары) - выход из цикла.
;=====================================================================
 
(defun C:LEP-SPAN (/ Route RouteID VClass Verts P1 P2 Idx1 Idx2 SubVerts LineType WireList WireChoice
                     LayerName LtName LtFile SpanEnt SpanLength RealLength DimDistance
                     Status OldOs OldError LEP-CatchResult)

    (setq OldError *error*)
    (defun *error* (msg)
        (if OldOs (setvar "OSMODE" OldOs))
        (setq *error* OldError)
        (princ (strcat "\nКоманда прервана: " msg))
        (princ)
    )

    (LEP:PrintHeader "Обработка пролётов и подписи")

    (setq Route (car (entsel "\nВыберите полилинию маршрута (если не видна - включите LEP-ROUTEVIS): ")))

    (if Route
        (progn
            ;; ID трассы - записываем его же в XDATA каждого пролёта
            ;; (ключ "ROUTE"), чтобы LEP-REPORT потом мог сгруппировать
            ;; метраж провода/кабеля по трассам - раньше пролёты вообще
            ;; не хранили, к какой трассе относятся (в отличие от опор).
            ;; Если выбранный объект почему-то без ID (не наш маршрут,
            ;; или старый объект без XDATA) - подстраховка, как и в
            ;; LEP-POLE.LSP, чтобы strcat в LEP:SetData не упал на nil.
            (setq RouteID (LEP:GetDataValue Route "ID"))
            (if (not RouteID) (setq RouteID "LEP_ROUTE_UNKNOWN"))

            ;; Класс напряжения маршрута - выбран один раз при LEP-ROUTE,
            ;; определяет, какой список марок ВЛ-провода предложить ниже
            ;; (СИП-3 для 10кВ, СИП-2 для 0,4кВ - разные провода физически,
            ;; путать нельзя, см. *LEP-WireTypes-VL-10*/-VL-04* в CONFIG).
            (setq VClass (LEP:GetDataValue Route "VCLASS"))

            (setq Verts (LEP:GetVertices Route))
 
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

                            (if P2
                                (progn
                                    ;; Находим ближайшие вершины маршрута к P1 и P2
                                    (setq Idx1 (LEP:GetNearestVertexIndex Verts P1))
                                    (setq Idx2 (LEP:GetNearestVertexIndex Verts P2))

                                    ;; Берём подсписок вершин между ними (по возрастанию индекса)
                                    (if (> Idx1 Idx2)
                                        (progn (setq Idx1 (LEP:GetNearestVertexIndex Verts P2))
                                               (setq Idx2 (LEP:GetNearestVertexIndex Verts P1)))
                                    )
                                    (setq SubVerts
                                        (LEP:SubList Verts Idx1 Idx2)
                                    )

                                    (if (< (length SubVerts) 2)
                                        (princ "\n[LEP-SPAN] Между этими точками нет отдельного участка маршрута - пропускаю.")
                                        (progn
                                            ;; Тип прокладки
                                            (setq LineType
                                                (LEP:ChooseFromList
                                                    (list (cons "ВЛ (воздух)" "VL") (cons "КЛ (земля)" "KL"))
                                                    "Тип прокладки"
                                                )
                                            )

                                            (if LineType
                                                (progn
                                                    (if (= (cdr LineType) "VL")
                                                        (progn
                                                            ;; СИП-3 - только для 10кВ (магистраль), СИП-2 -
                                                            ;; только для 0,4кВ (низкое напряжение) - список
                                                            ;; марок выбирается по классу МАРШРУТА, а не
                                                            ;; предлагается общий на оба случая.
                                                            (if (= VClass "10")
                                                                (setq WireList *LEP-WireTypes-VL-10*)
                                                                (setq WireList *LEP-WireTypes-VL-04*)
                                                            )
                                                            (setq LayerName *LEP-Layer-Proj-VL*)
                                                            (setq LtName "CONTINUOUS")
                                                            (setq LtFile "")
                                                        )
                                                        (progn
                                                            (setq WireList *LEP-WireTypes-KL*)
                                                            (setq LayerName *LEP-Layer-Proj-KL*)
                                                            (setq LtName *LEP-Linetype-KL*)
                                                            (setq LtFile *LEP-LinetypeFile-KL*)
                                                        )
                                                    )

                                                    (LEP:EnsureLinetypeLoaded LtName LtFile)

                                                    ;; Марка провода/кабеля - список из CONFIG
                                                    (setq WireChoice (LEP:ChooseFromList WireList "Марка провода/кабеля"))

                                                    (if WireChoice
                                                        (progn
                                                            (setq Status (LEP:GetStatus "пролёта"))

                                                            (setq SpanEnt (LEP:CreateSpanEntity SubVerts LayerName LtName))

                                                            ;; SpanLength - геометрический путь вдоль трассы (может
                                                            ;; не совпадать с прямым расстоянием P1-P2, если между
                                                            ;; опорами есть изгиб без опоры) - основа для расчёта
                                                            ;; РЕАЛЬНОЙ длины материала с запасом (RealLength).
                                                            ;; DimDistance - ПРЯМОЕ расстояние между самими опорами,
                                                            ;; для размерной линии - отдельная величина, см. шапки
                                                            ;; LEP:GetRealLength / LEP:CreateSpanDimension выше.
                                                            (setq SpanLength (LEP:GetSpanLength SubVerts))
                                                            (setq RealLength (LEP:GetRealLength (cdr LineType) SpanLength))
                                                            (setq DimDistance (LEP:RoundNearest (distance P1 P2)))

                                                            ;; Данные для ведомости: трасса, статус, марка, сечение,
                                                            ;; РЕАЛЬНАЯ длина с запасом (не сырое расстояние) - чтобы
                                                            ;; ведомость и подпись на чертеже показывали одно и то же.
                                                            (LEP:SetData SpanEnt
                                                                (list
                                                                    (cons "TYPE" "SPAN")
                                                                    (cons "ROUTE" RouteID)
                                                                    (cons "STATUS" Status)
                                                                    (cons "WIRE" (car WireChoice))
                                                                    (cons "SECTION" (cdr WireChoice))
                                                                    (cons "LENGTH" (itoa RealLength))
                                                                )
                                                            )

                                                            (LEP:CreateSpanLabel SubVerts (car WireChoice) RealLength Status)
                                                            (LEP:CreateSpanDimension P1 P2 DimDistance)
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
 
 
(princ "\nLEP-SPAN v0.5 загружен (клик только по настоящей опоре, не по откосу).")
(princ)