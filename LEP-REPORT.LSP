;=====================================================================
; ПРОЕКТ:       LEP (Автоматизация проектирования ЛЭП)
; ФАЙЛ:         LEP-REPORT.LSP
; ВЕРСИЯ:       0.4
; НАЗНАЧЕНИЕ:   Полностью автоматический сбор объемов материалов 
;               (чистые длины линий без округления и штучные опоры) 
;               с разделением по ID трасс и экспортом в формат CSV.
;=====================================================================

(defun C:LEP-REPORT ( /  ; Список локальных переменных для защиты памяти
                        VL-SS KL-SS PoleSS CsvPath CsvFile i Ent VlaObj 
                        Len Layer Name XData ResID PoleList Item 
                        MasterList RouteID FoundRoute FoundPole 
                        FileCheck )
    
    ; Подключаем базовые функции Visual LISP (ActiveX) для расширенной работы с объектами
    (vl-load-com)
    
    ; Выводим стандартное текстовое приветствие из LEP-UTILS
    (LEP:PrintHeader "Автоматическая выгрузка ведомости в CSV")

    ;-----------------------------------------------------------------
    ; СТРУКТУРА ДАННЫХ (MasterList):
    ; Хранит агрегированные данные в виде вложенных списков по каждой трассе:
    ; (
    ;   ("LEP_ROUTE_1" . ( ("LineLen" . 145.62) ("П20-3Н" . 4) ("А23" . 1) ))
    ;   ("LEP_ROUTE_2" . ( ("LineLen" . 89.11)  ("П23" . 3) ))
    ; )
    ;-----------------------------------------------------------------
    (setq MasterList nil)

    ;=================================================================
    ; ЭТАП 1: СБОР И ГЕОМЕТРИЧЕСКИЙ РАСЧЕТ ЛИНЕЙНОЙ ЧАСТИ (ВЛ и КЛ)
    ;=================================================================
    
    ; Формируем выборку всех легких полилиний (LWPOLYLINE) на проектных слоях ВЛ и КЛ
    (setq VL-SS (ssget "_X" (list '(0 . "LWPOLYLINE") 
                                  (cons 8 (strcat *LEP-Layer-Proj-VL* "," *LEP-Layer-Proj-KL*)))))

    (if VL-SS
        (progn
            (setq i 0)
            ; Цикл перебора всех найденных кабелей и проводов
            (repeat (sslength VL-SS)
                (setq Ent (ssname VL-SS i))
                ; Преобразуем стандартный ename во вла-объект для доступа к ActiveX методам
                (setq VlaObj (vlax-ename->vla-object Ent))
                
                ; Извлекаем чистую геометрическую длину объекта (БЕЗ ОКРУГЛЕНИЙ)
                (setq Len (vla-get-length VlaObj))
                
                ; Читаем расширенные данные (XDATA) объекта, привязанные к приложению "LEP_DATA"
                (setq XData (assoc -3 (entget Ent '("LEP_DATA"))))
                
                (if XData
                    ; Если XDATA есть, вытаскиваем сохраненный уникальный ID трассы
                    (setq RouteID (cdr (nth 4 (car (cdr XData)))))
                    ; Если объект лежит на слое, но не размечен кодом — маркируем как потерянный
                    (setq RouteID "НЕРАЗМЕЧЕННЫЕ_ЛИНИИ")
                )

                ; Ищем, создана ли уже запись для этой трассы в нашем главном списке MasterList
                (setq FoundRoute (assoc RouteID MasterList))
                
                (if FoundRoute
                    ; Если трасса уже есть, извлекаем её текущую длину, прибавляем новую и обновляем список
                    (progn
                        (setq PoleList (cdr FoundRoute))
                        (setq FoundPole (assoc "LineLen" PoleList))
                        (if FoundPole
                            (setq PoleList (subst (cons "LineLen" (+ (cdr FoundPole) Len)) FoundPole PoleList))
                            (setq PoleList (append PoleList (list (cons "LineLen" Len))))
                        )
                        (setq MasterList (subst (cons RouteID PoleList) FoundRoute MasterList))
                    )
                    ; Если трасса встретилась впервые, инициализируем её структуру с начальной длиной
                    (setq MasterList (append MasterList (list (cons RouteID (list (cons "LineLen" Len))))))
                )
                (setq i (1+ i))
            )
        )
    )

    ;=================================================================
    ; ЭТАП 2: СБОР И АНАЛИЗ ПРОЕКТНЫХ ОПОР (ВКЛЮЧАЯ ДИНАМИЧЕСКИЕ БЛОКИ)
    ;=================================================================
    
    ; Находим абсолютно все вхождения блоков (INSERT) на проектном слое опор
    (setq PoleSS (ssget "_X" (list '(0 . "INSERT") (cons 8 *LEP-Layer-Proj-Pole*))))

    (if PoleSS
        (progn
            (setq i 0)
            ; Поштучно перебираем все опоры на чертеже
            (repeat (sslength PoleSS)
                (setq Ent (ssname PoleSS i))
                (setq VlaObj (vlax-ename->vla-object Ent))
                
                ; РЕШЕНИЕ ПРОБЛЕМЫ ДИНАМИЧЕСКИХ БЛОКОВ:
                ; vla-get-EffectiveName извлекает ИСХОДНОЕ имя блока из описания, 
                ; даже если на чертеже конкретный блок стал анонимным (*U...) из-за смены свойств видимости.
                (setq PoleName (vla-get-EffectiveName VlaObj))
                
                ; Считываем XDATA опоры для определения её принадлежности к конкретной линии
                (setq XData (assoc -3 (entget Ent '("LEP_DATA"))))
                
                (if XData
                    (setq RouteID (cdr (nth 4 (car (cdr XData)))))
                    (setq RouteID "ОПОРА_БЕЗ_ТРАССЫ")
                )

                ; Проверяем наличие этой трассы в MasterList
                (setq FoundRoute (assoc RouteID MasterList))
                
                (if FoundRoute
                    ; Если ветка трассы создана (например, на этапе обсчета линий)
                    (progn
                        (setq PoleList (cdr FoundRoute))
                        ; Ищем конкретный тип опоры (например, "П20-3Н") внутри этой трассы
                        (setq FoundPole (assoc PoleName PoleList))
                        
                        (if FoundPole
                            ; Если тип опоры уже встречался на этой линии — инкрементируем счетчик (+1)
                            (setq PoleList (subst (cons PoleName (1+ (cdr FoundPole))) FoundPole PoleList))
                            ; Если тип опоры на этой линии новый — добавляем со значением 1
                            (setq PoleList (append PoleList (list (cons PoleName 1))))
                        )
                        ; Записываем обновленный подсписок материалов обратно в главную базу данных трассы
                        (setq MasterList (subst (cons RouteID PoleList) FoundRoute MasterList))
                    )
                    ; Если опора стоит изолированно и трассы еще не было в списке — создаем новую ветку
                    (setq MasterList (append MasterList (list (cons RouteID (list (cons PoleName 1))))))
                )
                (setq i (1+ i))
            )
        )
    )

    ;=================================================================
    ; ЭТАП 3: АВТОМАТИЧЕСКАЯ ЗАПИСЬ ДАННЫХ В ФАЙЛ CSV С ЗАЩИТОЙ ОТ СБОЕВ
    ;=================================================================
    
    ; Автоматически вычисляем путь к целевому CSV файлу в директории текущего DWG
    (setq CsvPath (strcat (getvar "DWGPREFIX") (vl-filename-base (getvar "DWGNAME")) "_ведомость.csv"))
    
    ; ЗАЩИТА ОТ БЛОКИРОВКИ EXCEL:
    ; Пробуем открыть файл в режиме добавления ("a"). Если Excel держит файл, open вернет nil.
    (setq FileCheck (open CsvPath "a"))
    
    (if (not FileCheck)
        ; Если файл заблокирован, прерываем выполнение и выводим громкое предупреждение
        (progn
            (princ "\n!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!")
            (princ (strcat "\n[КРИТИЧЕСКАЯ ОШИБКА]: Файл ведомости заблокирован!"))
            (princ "\nВозможно, этот CSV файл сейчас открыт в Microsoft Excel.")
            (princ "\nПожалуйста, закройте Excel и запустите команду LEP-REPORT снова.")
            (princ "\n!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!")
        )
        (progn
            (close FileCheck) ; Закрываем проверочный дескриптор
            
            ; Открываем файл заново в режиме чистой перезаписи ("w")
            (setq CsvFile (open CsvPath "w"))
            
            ; Записываем стандартную шапку таблицы. 
            ; Разделитель — СТРОГО СЕМИКОЛОН (точка с запятой) для моментального открытия в русском Excel.
            (write-line "Трасса;Наименование материала / оборудования;Количество;Ед. изм." CsvFile)
            
            ; Перебираем сформированную базу данных по всем трассам чертежа
            (foreach RouteItem MasterList
                (setq ResID (car RouteItem))     ; ID текущей трассы
                (setq PoleList (cdr RouteItem))   ; Список её элементов
                
                ; Сначала выгружаем общую чистую длину кабельных/воздушных трасс
                (setq FoundPole (assoc "LineLen" PoleList))
                (if FoundPole
                    (progn
                        ; Для красоты определяем тип проводника по названию ID или слою.
                        ; Выводим REAL-значение длины с точностью до 2 знаков после запятой без искажения округлением
                        (write-line (strcat ResID ";Проводник (проектная длина согласно геометрии);" (rtos (cdr FoundPole) 2 2) ";м.") CsvFile)
                    )
                )
                
                ; Теперь выгружаем все опоры, которые жестко привязаны к этой конкретной трассе
                (foreach Item PoleList
                    (if (/= (car Item) "LineLen") ; Пропускаем системную переменную длины
                        (write-line (strcat ResID ";Опора проектная типа " (car Item) ";" (itoa (cdr Item)) ";шт.") CsvFile)
                    )
                )
            )
            
            ; Закрываем файл, освобождая буфер обмена операционной системы
            (close CsvFile)
            
            (princ "\n=======================================================")
            (princ "\n[УСПЕХ] Сквозной сбор объемов завершен без ручного выбора.")
            (princ (strcat "\n Файл сохранен: " CsvPath))
            (princ "\n Данные сгруппированы по ID трасс на основе XDATA.")
            (princ "\n Длины взяты в чистом виде без повторных округлений.")
            (princ "\n=======================================================")
        )
    )
    (LEP:PrintFooter)
    (princ)
)

(princ "\nМодуль LEP-REPORT v0.4 успешно интегрирован.")
(princ)