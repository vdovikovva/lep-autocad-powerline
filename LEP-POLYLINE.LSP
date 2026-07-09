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



;=====================================================================
;
; LEP:GetVertexCount
;
;=====================================================================

(defun LEP:GetVertexCount (Ent)

    (length

        (LEP:GetVertices Ent)

    )

)



;=====================================================================
;
; LEP:GetSegmentLength
;
; Возвращает длину между двумя соседними вершинами.
;
;=====================================================================

(defun LEP:GetSegmentLength

(

Ent

Index

/

Vertices

P1

P2

)

    (setq Vertices

        (LEP:GetVertices Ent)

    )

    (setq P1

        (nth Index Vertices)

    )

    (setq P2

        (nth

            (+ Index 1)

            Vertices

        )

    )

    (distance P1 P2)

)



;=====================================================================
;
; LEP:GetSegmentList
;
; Возвращает список длин всех пролетов.
;
;=====================================================================

(defun LEP:GetSegmentList

(

Ent

/

Vertices

Result

i

)

    (setq Vertices

        (LEP:GetVertices Ent)

    )

    (setq Result nil)

    (setq i 0)

    (repeat

        (- (length Vertices) 1)

        (setq Result

            (append

                Result

                (list

                    (distance

                        (nth i Vertices)

                        (nth (+ i 1) Vertices)

                    )

                )

            )

        )

        (setq i (1+ i))

    )

    Result

)



(princ "\nLEP-POLYLINE загружен.")

(princ)