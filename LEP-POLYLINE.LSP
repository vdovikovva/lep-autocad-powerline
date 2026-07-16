;=====================================================================
;
;   ПРОЕКТ:
;   LEP
;
;   ФАЙЛ:
;   LEP-POLYLINE.LSP
;
;   Работа с полилиниями.
;
;   ПОЧИЩЕНО (аудит перед сном - Claude): раньше здесь были ещё
;   LEP:GetVertexCount, LEP:GetSegmentLength, LEP:GetSegmentList -
;   нигде в проекте не вызывались, убраны. Также раньше в LEP-POLE.LSP
;   была своя копия LEP:GetVertices под именем LEP:GetVertexList,
;   делавшая ровно то же самое - оставлена только одна версия, здесь,
;   как "общая для всех" (этот файл грузится раньше POLE/ROUTE/SPAN).
;
;=====================================================================



;=====================================================================
;
; LEP:GetVertices
;
; Возвращает список всех вершин LWPOLYLINE.
;
; Вход:
;
; ename
;
; Выход:
;
; (
;   (x y)
;   (x y)
;   ...
; )
;
; Точки ДВУМЕРНЫЕ - у LWPOLYLINE группа 10 хранит только (x y), без
; Z (комментарий поправлен при аудите 2026-07-11 - раньше обещал
; (x y z), что не соответствовало действительности; весь код проекта
; и так работает с этими точками корректно: distance/angle/entmake
; принимают 2D-точки).
;
;=====================================================================

(defun LEP:GetVertices (Ent / Data Result Item)

    (setq Data (entget Ent))

    (setq Result nil)

    (foreach Item Data

        (if (= (car Item) 10)

            (setq Result

                (append

                    Result

                    (list

                        (cdr Item)

                    )

                )

            )

        )

    )

    Result

)


;=====================================================================
;
; LEP:GetPointAtDistance
;
; Точка на трассе (список вершин Verts) на расстоянии Dist (метров,
; ВДОЛЬ полилинии, не по прямой) от вершины с индексом FromIdx, в
; направлении Forward (T - к ПОСЛЕДНЕЙ вершине списка, растущий
; индекс; nil - к ПЕРВОЙ, убывающий индекс).
;
; Нужна для LEP-POLE.LSP (2026-07-15, по просьбе пользователя) -
; позволяет ВВЕСТИ расстояние от предыдущей опоры числом вместо того,
; чтобы кликать мышкой "на глаз" и потом вручную двигать опоры под
; нужный шаг (по изысканиям для Сущ. или по проектной норме для
; Проект.).
;
; Если Dist больше, чем осталось полилинии в заданном направлении -
; ПРОДОЛЖАЕТ ПРЯМО за пределами полилинии, в направлении ПОСЛЕДНЕГО
; пройденного отрезка - тот же приём, что уже используется в
; LEP-END.LSP для опор МТП/ЩУ, стоящих за концом трассы.
;
; Направление Forward - определяется ОДИН РАЗ вызывающим кодом (по
; тому, к какой вершине маршрута ближе ПЕРВАЯ опора сессии - см.
; LEP-POLE.LSP), не пересчитывается здесь.
;
;=====================================================================

(defun LEP:GetPointAtDistance (Verts FromIdx Dist Forward / Step Idx A B SegLen Remaining Result LastDir LastVert PrevIdx)

    (setq Step (if Forward 1 -1))
    (setq Idx FromIdx)
    (setq Remaining Dist)
    (setq Result nil)

    ;; Направление "по умолчанию", если идти вообще некуда (FromIdx уже
    ;; крайняя вершина в нужную сторону) - берём направление отрезка,
    ;; ВЕДУЩЕГО в FromIdx с той же стороны, откуда пришли (а не 0.0
    ;; "в никуда"), чтобы экстраполяция ниже всё равно легла вдоль
    ;; трассы, а не горизонтально куда попало.
    (setq PrevIdx (- FromIdx Step))
    (setq LastDir
        (if (and (>= PrevIdx 0) (< PrevIdx (length Verts)))
            (angle (nth PrevIdx Verts) (nth FromIdx Verts))
            0.0
        )
    )
    (setq LastVert (nth FromIdx Verts))

    (while (and (not Result)
                (>= (+ Idx Step) 0)
                (< (+ Idx Step) (length Verts))
           )
        (setq A (nth Idx Verts))
        (setq B (nth (+ Idx Step) Verts))
        (setq SegLen (distance A B))
        (setq LastDir (angle A B))
        (setq LastVert B)

        (if (<= Remaining SegLen)
            (setq Result (polar A LastDir Remaining))
            (progn
                (setq Remaining (- Remaining SegLen))
                (setq Idx (+ Idx Step))
            )
        )
    )

    (if (not Result)
        ;; Полилиния кончилась раньше, чем набралось нужное расстояние -
        ;; продолжаем ПРЯМО в направлении последнего отрезка.
        (setq Result (polar LastVert LastDir Remaining))
    )

    Result
)



(princ "\nLEP-POLYLINE загружен.")

(princ)
