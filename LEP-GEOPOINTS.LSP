;=====================================================================
;
;   ПРОЕКТ:      LEP
;   ФАЙЛ:        LEP-GEOPOINTS.LSP
;   ВЕРСИЯ:      0.2  (файлы переехали в папку ЧЕРТЕЖА (DWGPREFIX),
;                вместо папки geojson; DRAW больше не спрашивает файл
;                диалогом; EXTRACT создаёт пустой geopoints-converted.txt
;                - Claude, 2026-07-20, по просьбе пользователя после
;                успешного первого живого теста)
;   0.1  (первая версия - Claude, 2026-07-20)
;
;   НАЗНАЧЕНИЕ:
;
;   Ставит на чертёж временные зелёные кружки-ориентиры в тех точках,
;   где по GPS (полевой замер, экспорт в GeoJSON) должны стоять опоры -
;   чтобы пользователь мог рядом вручную расставить настоящие символы
;   опор (обычно Сущ.). Кружки НЕ часть готового чертежа, только рабочая
;   подсказка - есть отдельная команда, которая их все стирает разом.
;
;   ⚕️ ПОЧЕМУ ТРИ ШАГА, А НЕ ОДНА КОМАНДА "GEOJSON -> ЧЕРТЁЖ" СРАЗУ:
;
;   GeoJSON хранит координаты в WGS84 (широта/долгота - обычный GPS),
;   а чертёж/подоснова - в МСК-47 (местная система координат для
;   кадастровых работ в Ленобласти, зона 2, официальный код в реестре
;   EPSG:6334702). Перевод WGS84 -> МСК-47 - это полноценная геодезическая
;   трансформация (смена датума + проекция Гаусса-Крюгера + поправки),
;   не тривиальная формула. Первая идея (подогнать свою формулу
;   полиномиальной регрессией по 25 калибровочным точкам одного
;   участка) была проверена и ОТВЕРГНУТА - см. LEP-README.md, раздел
;   "GPS-точки/GeoJSON" - формула идеально легла на калибровочные точки
;   (расхождение <1см), но у КАЖДОЙ зоны МСК-47 своё смещение и своя
;   нелинейность проекции, локальная подгонка одного участка не
;   переживает переезд на другой (подтверждено пользователем - "на трёх
;   зонах и везде своё смещение"). Поэтому сам перевод координат в LISP
;   НЕ делается - пользователь считает его через проверенный сайт-конвертер
;   (с официальным кодом EPSG, не самодельное приближение), а LISP
;   только читает готовый результат. Три команды ниже соответствуют трём
;   шагам этого процесса:
;
;     1. LEP-GEOPOINTS-EXTRACT - ЕДИНСТВЕННЫЙ шаг с ручным выбором файла
;        (getfiled на geojson) - ✅ ФИКС 2026-07-20 по просьбе
;        пользователя: раньше coords/names писались РЯДОМ С GEOJSON
;        (могла оказаться вообще другая папка, например ~/Downloads),
;        теперь - рядом с САМИМ ЧЕРТЕЖОМ (DWGPREFIX, тот же приём, что и
;        у CSV в LEP-REPORT.LSP), т.к. именно там пользователь и
;        работает дальше. Создаёт три файла: geopoints-coords.txt
;        (только "широта,долгота", по строке на точку - специально БЕЗ
;        названий, чтобы можно было выделить весь файл и вставить в
;        конвертер одним действием, не вычищая лишнее руками),
;        geopoints-names.txt (только названия точек, в ТОМ ЖЕ порядке
;        строк - хранится "за кулисами", пока конвертер работает только
;        с координатами) и ПУСТОЙ geopoints-converted.txt (только если
;        его ещё нет - см. ⚠️ ниже, чтобы не затереть уже вставленный
;        пользователем результат конвертера при повторном EXTRACT).
;
;     2. (ручной шаг пользователя) - открыть geopoints-coords.txt,
;        скопировать всё, вставить в конвертер WGS84 -> МСК-47 зона 2,
;        результат вставить в уже готовый geopoints-converted.txt (тот
;        же, что создал шаг 1 - рядом с чертежом) и сохранить.
;
;     3. LEP-GEOPOINTS-DRAW - БЕЗ диалога выбора файла (✅ ФИКС
;        2026-07-20): сама читает geopoints-converted.txt и
;        geopoints-names.txt из папки чертежа (DWGPREFIX). Сверяет
;        количество строк (при расхождении - громкая ошибка, НИЧЕГО не
;        рисует, чтобы не перепутать название с чужой точкой), рисует
;        зелёный круг + подпись рядом с ним для каждой точки.
;
;   ⚠️ ПЕРЕСТАНОВКА X/Y: конвертер отдаёт "N,E" (северная, восточная) -
;   это НЕ то же самое, что X,Y чертежа. У подосновы этого проекта
;   чертёжный X - это как раз "восточная" (~2 250 000 - смещение зоны 2
;   МСК-47), а чертёжный Y - "северная" (~450 000-460 000) - проверено
;   разбором реального текстового объекта на подоснове (см. переписку
;   2026-07-20 в истории чата/README). LEP:GeoPoints-DrawOne ниже эту
;   перестановку делает - см. комментарий прямо в коде, ⚠️ НЕ УБИРАТЬ.
;
;   ⚠️ ПАРСЕР GEOJSON - НЕ полноценный JSON-парсер (в AutoLISP нет ни
;   regex, ни готовой JSON-библиотеки), а узкий разбор ПОД КОНКРЕТНУЮ
;   структуру экспорта (Point-геометрия, "coordinates": [lon, lat],
;   "properties": {"name": "..."}), основанный на vl-string-search/
;   substr. Если формат экспорта когда-нибудь изменится (другой сервис
;   карт, вложенные структуры) - парсер придётся поправить.
;
;=====================================================================



;=====================================================================
;                       СЛУЖЕБНАЯ ФУНКЦИЯ
;=====================================================================
;
; LEP:GJ-Trim
;
; Убирает пробелы по краям строки - в AutoLISP нет готовой функции
; trim, а после разбора "[ 30.89, 60.10 ]" на "30.89"/" 60.10 " лишние
; пробелы мешают (setq LatStr (LEP:GJ-Trim ...))->(atof ...): atof
; ведущий пробел обычно переживает нормально, а вот хвостовые символы
; после числа - не гарантировано, поэтому чистим с обеих сторон.
;
;=====================================================================

(defun LEP:GJ-Trim (s / i j n)
    (setq n (strlen s))
    (setq i 1)
    (while (and (<= i n) (= (substr s i 1) " "))
        (setq i (1+ i))
    )
    (setq j n)
    (while (and (>= j i) (= (substr s j 1) " "))
        (setq j (1- j))
    )
    (if (>= j i)
        (substr s i (1+ (- j i)))
        ""
    )
)



;=====================================================================
;                       СЛУЖЕБНАЯ ФУНКЦИЯ
;=====================================================================
;
; LEP:GeoJSON-Parse (Path)
;
; Читает GeoJSON-файл целиком в одну строку (построчно через read-line,
; со склейкой пробелом - файл экспорта "человекочитаемый", каждое число
; координаты на своей строке, склейка пробелом восстанавливает
; "[ 30.89, 60.10 ]" в одну строку для поиска) и вытаскивает из каждой
; Point-фичи пару координат + название.
;
; Возвращает список списков (LonStr LatStr Name) - строки, не реалы
; (незачем терять исходную точность через atof->rtos, просто переносим
; текст как есть в файл geopoints-coords.txt).
;
; ⚠️ Порядок в GeoJSON - [долгота, широта] (стандарт GeoJSON), поэтому
; LonStr идёт ПЕРВЫМ в возвращаемой паре - не перепутать при записи в
; geopoints-coords.txt (там нужно "широта,долгота", см. ниже в EXTRACT).
;
;=====================================================================

(defun LEP:GeoJSON-Parse (Path / F Line FullText Pos NamePos CoordStart CoordEnd CoordStr CommaPos LonStr LatStr NameStart NameEnd Name Result)
    (setq F (open Path "r"))
    (if (not F)
        (progn
            (princ (strcat "\n[LEP-GEOPOINTS] Не могу открыть файл: " Path))
            nil
        )
        (progn
            (setq FullText "")
            (while (setq Line (read-line F))
                (setq FullText (strcat FullText Line " "))
            )
            (close F)

            (setq Result '())
            (setq Pos 0)
            (while (setq Pos (vl-string-search "\"coordinates\"" FullText Pos))
                (setq CoordStart (vl-string-search "[" FullText Pos))
                (setq CoordEnd (vl-string-search "]" FullText CoordStart))
                (setq CoordStr (substr FullText (+ CoordStart 2) (- CoordEnd CoordStart 1)))
                (setq CommaPos (vl-string-search "," CoordStr))
                (setq LonStr (LEP:GJ-Trim (substr CoordStr 1 CommaPos)))
                (setq LatStr (LEP:GJ-Trim (substr CoordStr (+ CommaPos 2))))

                ;; Название - ищем "name" ПОСЛЕ текущих координат. Если
                ;; вдруг не найдено (экспорт без properties.name) - не
                ;; падаем, просто оставляем пустую строку, чтобы одна
                ;; точка без названия не обрушила разбор всего файла.
                (setq NamePos (vl-string-search "\"name\"" FullText CoordEnd))
                (if NamePos
                    (progn
                        (setq NameStart (vl-string-search "\"" FullText (+ NamePos 6)))
                        (setq NameEnd (vl-string-search "\"" FullText (1+ NameStart)))
                        (setq Name (substr FullText (+ NameStart 2) (- NameEnd NameStart 1)))
                    )
                    (setq Name "")
                )

                (setq Result (append Result (list (list LonStr LatStr Name))))
                (setq Pos (1+ CoordEnd))
            )
            Result
        )
    )
)



;=====================================================================
;                       ОСНОВНАЯ КОМАНДА (ШАГ 1)
;=====================================================================
;
; C:LEP-GEOPOINTS-EXTRACT
;
; Диалог выбора GeoJSON (getfiled - ЕДИНСТВЕННЫЙ ручной выбор файла во
; всей цепочке шагов 1-3) -> разбор -> три файла РЯДОМ С ЧЕРТЕЖОМ
; (DWGPREFIX, не рядом с geojson - см. ⚠️ ФИКС 2026-07-20 в шапке
; файла): geopoints-coords.txt (широта,долгота - готово для вставки в
; конвертер), geopoints-names.txt (названия, тот же порядок строк) и
; ПУСТОЙ geopoints-converted.txt, куда пользователь вставит результат
; конвертера. Печатает пути и краткую подсказку, что делать дальше.
;
; ⚠️ geopoints-converted.txt создаётся ПУСТЫМ только если его ЕЩЁ НЕТ -
; при повторном запуске EXTRACT (например, добавили новые точки в
; geojson) уже вставленный пользователем результат конвертера НЕ
; затирается молча.
;
;=====================================================================

(defun C:LEP-GEOPOINTS-EXTRACT (/ GeoJsonPath Folder Points CoordsPath NamesPath ConvertedPath CF NF TestF Item Count)

    (setq GeoJsonPath (getfiled "Выберите файл GeoJSON с координатами точек" "" "geojson" 0))

    (if (not GeoJsonPath)
        (princ "\n[LEP-GEOPOINTS] Отменено пользователем.")
        (progn
            (setq Points (LEP:GeoJSON-Parse GeoJsonPath))

            (if (not Points)
                (princ "\n[LEP-GEOPOINTS] Не найдено ни одной точки (coordinates) в файле - ничего не сохранено.")
                (progn
                    ;; Рядом с ЧЕРТЕЖОМ, не с geojson - DWGPREFIX уже
                    ;; включает завершающий разделитель пути (тот же
                    ;; приём, что и в LEP-REPORT.LSP при записи CSV).
                    (setq Folder (getvar "DWGPREFIX"))
                    (setq CoordsPath (strcat Folder "geopoints-coords.txt"))
                    (setq NamesPath (strcat Folder "geopoints-names.txt"))
                    (setq ConvertedPath (strcat Folder "geopoints-converted.txt"))

                    ;; coords.txt - только цифры/точка/запятая, кириллицы
                    ;; нет - обычный "w" без BOM, чтобы никакой невидимый
                    ;; служебный символ не попал в буфер обмена при вставке
                    ;; в конвертер.
                    (setq CF (open CoordsPath "w"))

                    ;; names.txt - кириллица, здесь BOM нужен (см. урок
                    ;; проекта про UTF-8 без BOM в LEP-REPORT.LSP/CSV -
                    ;; тот же принцип, любой файл с кириллицей = utf8-bom).
                    (setq NF (open NamesPath "w" "utf8-bom"))

                    (setq Count 0)
                    (foreach Item Points
                        ;; Item = (LonStr LatStr Name) - широта ПЕРВОЙ в
                        ;; coords.txt (конвертер ждёт "N,E" = широта,долгота -
                        ;; см. ⚠️ ПЕРЕСТАНОВКА X/Y в шапке файла).
                        (write-line (strcat (cadr Item) "," (car Item)) CF)
                        (write-line (caddr Item) NF)
                        (setq Count (1+ Count))
                    )

                    (close CF)
                    (close NF)

                    ;; Пустой converted.txt - только если его ещё нет
                    ;; (см. ⚠️ в шапке функции выше).
                    (setq TestF (open ConvertedPath "r"))
                    (if TestF
                        (progn
                            (close TestF)
                            (princ (strcat "\n  geopoints-converted.txt уже существует - не трогаю: " ConvertedPath))
                        )
                        (progn
                            (setq TestF (open ConvertedPath "w"))
                            (close TestF)
                            (princ (strcat "\n  Создан пустой geopoints-converted.txt: " ConvertedPath))
                        )
                    )

                    (princ (strcat "\n[LEP-GEOPOINTS] Извлечено точек: " (itoa Count)))
                    (princ (strcat "\n  Координаты (вставить в конвертер): " CoordsPath))
                    (princ (strcat "\n  Названия (не трогать):            " NamesPath))
                    (princ "\n\nДальше: откройте geopoints-coords.txt, скопируйте всё, вставьте в конвертер WGS84 -> МСК-47 зона 2, результат вставьте в geopoints-converted.txt и сохраните. Затем вызовите LEP-GEOPOINTS-DRAW.")
                )
            )
        )
    )
    (princ)
)



;=====================================================================
;                       ОСНОВНАЯ КОМАНДА (ШАГ 3)
;=====================================================================
;
; C:LEP-GEOPOINTS-DRAW
;
; БЕЗ диалога выбора файла (✅ ФИКС 2026-07-20, по просьбе пользователя -
; "выбирать руками надо только geojson") - сама читает
; geopoints-converted.txt и geopoints-names.txt из папки ЧЕРТЕЖА
; (DWGPREFIX, те же фиксированные имена, что и создаёт EXTRACT) ->
; сверка количества строк -> для каждой пары рисует зелёный круг +
; подпись на слое *LEP-Layer-GeoPoints*.
;
; ⚠️ Если количество строк не совпало - НИЧЕГО не рисуется вообще (не
; "рисуем сколько смогли") - при расхождении невозможно понять, какая
; строка какой точке соответствует, тихая частичная отрисовка привела
; бы к подписям на чужих точках без единого сообщения об ошибке.
;
;=====================================================================

(defun C:LEP-GEOPOINTS-DRAW (/ ConvPath Folder NamesPath CF NF Line CoordLines NameLines CommaPos NorthStr EastStr Northing Easting DrawPt LabelPt Radius i Name Count)

    (setq Folder (getvar "DWGPREFIX"))
    (setq ConvPath (strcat Folder "geopoints-converted.txt"))
    (setq NamesPath (strcat Folder "geopoints-names.txt"))

    (progn
        (setq CF (open ConvPath "r"))
        (setq NF (open NamesPath "r"))

        (if (not (and CF NF))
            (progn
                (princ (strcat "\n[LEP-GEOPOINTS] Не могу открыть один из файлов. Ожидались: " ConvPath " и " NamesPath ". Сначала вызовите LEP-GEOPOINTS-EXTRACT."))
                (if CF (close CF))
                (if NF (close NF))
            )
            (progn
                (setq CoordLines '())
                (while (setq Line (read-line CF))
                    (if (/= (LEP:GJ-Trim Line) "")
                        (setq CoordLines (append CoordLines (list Line)))
                    )
                )
                (close CF)

                (setq NameLines '())
                (while (setq Line (read-line NF))
                    (setq NameLines (append NameLines (list Line)))
                )
                (close NF)

                (if (/= (length CoordLines) (length NameLines))
                    (princ
                        (strcat
                            "\n[LEP-GEOPOINTS] ОШИБКА: количество строк не совпадает ("
                            (itoa (length CoordLines)) " координат против "
                            (itoa (length NameLines)) " названий) - НИЧЕГО не нарисовано."
                            " Проверьте geopoints-names.txt и результат конвертера - возможно,"
                            " конвертер потерял/добавил строку."
                        )
                    )
                    (progn
                        (setq Radius (/ *LEP-GeoPoints-Diameter* 2.0))
                        (setq Count 0)
                        (setq i 0)
                        (while (< i (length CoordLines))
                            (setq Line (nth i CoordLines))
                            (setq CommaPos (vl-string-search "," Line))
                            (setq NorthStr (LEP:GJ-Trim (substr Line 1 CommaPos)))
                            (setq EastStr (LEP:GJ-Trim (substr Line (+ CommaPos 2))))
                            (setq Northing (atof NorthStr))
                            (setq Easting (atof EastStr))
                            (setq Name (nth i NameLines))

                            ;; ⚠️ ПЕРЕСТАНОВКА X/Y - конвертер отдаёт
                            ;; "северная,восточная", а у чертежа этого
                            ;; проекта X = восточная (~2 250 000, зона 2
                            ;; МСК-47), Y = северная (~450-460 тыс.) -
                            ;; см. ⚠️ в шапке файла. Перепутать местами -
                            ;; точки уедут в другое место чертежа, не
                            ;; рядом с подосновой.
                            (setq DrawPt (list Easting Northing 0.0))
                            (setq LabelPt (list (+ Easting *LEP-GeoPoints-LabelOffset*) Northing 0.0))

                            (entmake
                                (list
                                    (cons 0 "CIRCLE")
                                    (cons 8 *LEP-Layer-GeoPoints*)
                                    (cons 10 DrawPt)
                                    (cons 40 Radius)
                                )
                            )

                            (if (/= Name "")
                                (entmake
                                    (list
                                        (cons 0 "TEXT")
                                        (cons 8 *LEP-Layer-GeoPoints*)
                                        (cons 10 LabelPt)
                                        (cons 40 *LEP-TextHeight*)
                                        (cons 1 Name)
                                        (cons 7 *LEP-TextStyle-Name*)
                                    )
                                )
                            )

                            (setq Count (1+ Count))
                            (setq i (1+ i))
                        )
                        (princ (strcat "\n[LEP-GEOPOINTS] Нарисовано точек: " (itoa Count)))
                    )
                )
            )
        )
    )
    (princ)
)



;=====================================================================
;                       ОСНОВНАЯ КОМАНДА (ОЧИСТКА)
;=====================================================================
;
; C:LEP-GEOPOINTS-CLEAR
;
; Стирает ВСЕ объекты со служебного слоя *LEP-Layer-GeoPoints* (круги +
; подписи) одной командой. Слой не удаляется, остаётся пустым для
; следующей партии.
;
;=====================================================================

(defun C:LEP-GEOPOINTS-CLEAR (/ SS i Count)
    (setq SS (ssget "_X" (list (cons 8 *LEP-Layer-GeoPoints*))))
    (if (not SS)
        (princ "\n[LEP-GEOPOINTS] На слое GeoPoints и так ничего нет.")
        (progn
            (setq Count (sslength SS))
            (setq i 0)
            (while (< i Count)
                (entdel (ssname SS i))
                (setq i (1+ i))
            )
            (princ (strcat "\n[LEP-GEOPOINTS] Удалено объектов: " (itoa Count)))
        )
    )
    (princ)
)



(princ "\n[LEP-GEOPOINTS] Модуль загружен - команды LEP-GEOPOINTS-EXTRACT / LEP-GEOPOINTS-DRAW / LEP-GEOPOINTS-CLEAR")
(princ)
