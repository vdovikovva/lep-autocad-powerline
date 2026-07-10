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
;   (x y z)
;   (x y z)
;   ...
; )
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


(princ "\nLEP-POLYLINE загружен.")

(princ)
