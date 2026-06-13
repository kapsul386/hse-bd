SET client_encoding TO 'UTF8';   -- файл в UTF-8; строка защищает от авто-WIN1252 на Windows
-- =====================================================================
-- SQL DML — запросы и транзакции   (проект «Перекус»)
<<<<<<< Updated upstream
-- Версия: v1.4 (проверено на PG 18.3/18.4 + seed.sql). Владелец: Роль 3.
=======
-- Версия: v1.4 (проверено на PG 18.4 + seed.sql). Владелец: Роль 3.
>>>>>>> Stashed changes
--   v1.2 (аудит 2026-06-10, одобрено командой): стражи в Q6 и T2,
--     Q8 без отменённых заказов, честная инструкция по применению.
--   v1.3 (решения команды 2026-06-10): Q13/Q14 под ФТ-12 (отзывы),
--     T1 проверяет О24 (способ оплаты принимается рестораном).
<<<<<<< Updated upstream
--   v1.4 (финальная сборка 2026-06-12): T1 считает промокод, проверяет все
--     запрошенные позиции и пишет payment.restaurant_id для декларативного О24.
=======
--   v1.4 (по замечаниям верификации 2-й моделью, раздел 14): T1 реализует
--     промокод О19/О20 (Z2); Q4 не теряет заказы без позиций (Z5); Q15 —
--     недостающий переход paid→cooking (Z4); страж оценки курьера в Q13 (Z9);
--     зафиксирована семантика выручки в Q9 (Z7). О24 теперь держит FK (Z3).
>>>>>>> Stashed changes
-- Применение: выполнять запросы ВЫБОРОЧНО после schema.sql + seed.sql.
--   Файл целиком через `psql -f dml.sql` НЕ пройдёт: :param — psql-плейсхолдеры,
--   их нужно задавать через `psql -v name=value` (Q8–Q12, Q14 параметров не требуют).
-- Для КАЖДОГО запроса: ФТ / Кто / Зачем.
-- Покрытие: 9 запросов CRUD (Q1–Q7, Q13, Q15) + 6 сложных (Q8–Q12, Q14) + 2 транзакции.
-- =====================================================================

-- #####################################################################
-- ЧАСТЬ A. Базовые операции (CRUD) — 7 запросов, покрывают C/R/U/D
-- #####################################################################

-- --- Q1 (CREATE) Регистрация клиента --------------------------------
-- ФТ-1 · клиент · завести учётную запись
INSERT INTO customer (full_name, phone, email)
VALUES (:name, :phone, :email)
RETURNING customer_id;

-- --- Q2 (CREATE) Добавить клиенту адрес доставки --------------------
-- ФТ-1 · клиент · сохранить адрес для будущих заказов
INSERT INTO address (customer_id, city, street, building, apartment, comment)
VALUES (:cust, :city, :street, :building, :apartment, :comment)
RETURNING address_id;

-- --- Q3 (READ) Меню ресторана по категориям -------------------------
-- ФТ-2 · клиент · показать только доступные блюда, сгруппированные по категориям
SELECT mc.name AS category, mi.name AS item, mi.price
FROM menu_item mi
JOIN menu_category mc ON mc.category_id = mi.category_id
WHERE mi.restaurant_id = :rest AND mi.is_available
ORDER BY mc.name, mi.name;

-- --- Q4 (READ) История заказов клиента ------------------------------
<<<<<<< Updated upstream
-- ФТ-8 · клиент · список заказов со стоимостью позиций, оплатой и статусом
SELECT o.order_id, o.created_at, r.name AS restaurant, o.status,
       SUM(oi.quantity * oi.unit_price) AS items_total_before_discount,
       p.amount AS paid_amount,
       p.status AS payment_status
FROM customer_order o
JOIN restaurant r  ON r.restaurant_id = o.restaurant_id
JOIN order_item oi ON oi.order_id = o.order_id
LEFT JOIN payment p ON p.order_id = o.order_id
=======
-- ФТ-8 · клиент · список заказов с суммой позиций (без скидки) и статусом
-- [v1.4, Z5 рецензента] LEFT JOIN: заказ без позиций (например, created в
-- момент оформления) не должен исчезать из истории клиента.
SELECT o.order_id, o.created_at, r.name AS restaurant, o.status,
       COALESCE(SUM(oi.quantity * oi.unit_price), 0) AS items_total
FROM customer_order o
JOIN restaurant r       ON r.restaurant_id = o.restaurant_id
LEFT JOIN order_item oi ON oi.order_id = o.order_id
>>>>>>> Stashed changes
WHERE o.customer_id = :cust
GROUP BY o.order_id, o.created_at, r.name, o.status, p.amount, p.status
ORDER BY o.created_at DESC;

-- --- Q5 (UPDATE) Изменение цены блюда -------------------------------
-- ФТ-9 · ресторан · меняет ТЕКУЩУЮ цену; снимки в прошлых заказах не затрагиваются
UPDATE menu_item SET price = :new_price WHERE item_id = :item;

-- --- Q6 (UPDATE) Назначить курьера и перевести заказ в доставку ------
-- ФТ-6 · оператор/курьер · назначение возможно только после оплаты/готовки
-- [аудит 2026-06-10] добавлен страж courier_id IS NULL (защита от двойного
-- назначения при гонке двух операторов): раздел 4 документа уже описывал Q6
-- именно так, код отставал от документа.
UPDATE customer_order
SET courier_id = :courier, status = 'on_the_way'
WHERE order_id = :order AND status IN ('paid', 'cooking')
  AND courier_id IS NULL;

-- --- Q7 (DELETE) Удалить НЕиспользуемый адрес клиента ----------------
-- ФТ-1 · клиент · удаляем адрес только если он не привязан ни к одному заказу
DELETE FROM address a
WHERE a.address_id = :addr
  AND NOT EXISTS (SELECT 1 FROM customer_order o WHERE o.address_id = a.address_id);

-- --- Q13 (CREATE) Оставить отзыв на доставленный заказ ---------------
-- ФТ-12 · клиент · оценить ресторан (обязательно) и курьера (опционально)
-- [v1.3] стражи: только СВОЙ заказ (:cust) и только 'delivered' (О26);
-- повторный отзыв отсечёт UNIQUE(order_id) (О25); оценки 1..5 держит CHECK (О27).
-- [v1.4, Z9 рецензента] оценка курьера пишется только если курьер был назначен.
INSERT INTO order_review (order_id, restaurant_rating, courier_rating, comment)
SELECT o.order_id, :rest_rating,
       CASE WHEN o.courier_id IS NOT NULL THEN :cour_rating END,
       :'comment'
FROM customer_order o
WHERE o.order_id = :order AND o.customer_id = :cust AND o.status = 'delivered'
RETURNING review_id;

-- --- Q15 (UPDATE) Ресторан принял заказ в готовку --------------------
-- ФТ-6 · ресторан · переход paid → cooking жизненного цикла (О22)
-- [v1.4, Z4 рецензента] этого перехода не было ни в одном запросе — заказ
-- не мог штатно попасть в 'cooking'.
UPDATE customer_order SET status = 'cooking'
WHERE order_id = :order AND status = 'paid';


-- #####################################################################
-- ЧАСТЬ B. Сложные запросы — 6 штук
-- (JOIN / GROUP BY / подзапросы / агрегаты / оконные функции)
-- #####################################################################

-- --- Q8 Топ-5 блюд каждого ресторана по продажам (оконная) ----------
-- ФТ-10 · ресторан · что лучше всего продаётся
-- [аудит 2026-06-10, одобрено командой] отменённые заказы исключены:
-- прежняя версия считала «продажами» и позиции cancelled-заказов.
SELECT * FROM (
    SELECT r.name AS restaurant, mi.name AS item,
           SUM(oi.quantity) AS sold,
           ROW_NUMBER() OVER (PARTITION BY r.restaurant_id
                              ORDER BY SUM(oi.quantity) DESC) AS rnk
    FROM order_item oi
    JOIN customer_order o ON o.order_id = oi.order_id AND o.status <> 'cancelled'
    JOIN menu_item mi ON mi.item_id = oi.item_id
    JOIN restaurant r ON r.restaurant_id = mi.restaurant_id
    GROUP BY r.restaurant_id, r.name, mi.item_id, mi.name
) t
WHERE rnk <= 5
ORDER BY restaurant, rnk;

-- --- Q9 Выручка по дням с нарастающим итогом (оконная) --------------
-- ФТ-10 · ресторан/оператор · динамика и накопленная выручка
-- [v1.4, Z7 рецензента] семантика зафиксирована: это ВАЛОВАЯ выручка по
-- оплатам со статусом 'paid' НА МОМЕНТ снятия отчёта; возвращённые оплаты
-- (refunded) исключаются целиком, поэтому отчёт за прошлые даты может
-- меняться после возвратов. Net-выручка с датами возвратов — вне объёма.
SELECT day, daily_revenue,
       SUM(daily_revenue) OVER (ORDER BY day) AS running_total
FROM (
    SELECT date_trunc('day', p.paid_at)::date AS day, SUM(p.amount) AS daily_revenue
    FROM payment p
    WHERE p.status = 'paid'
    GROUP BY 1
) d
ORDER BY day;

-- --- Q10 Среднее время доставки по курьерам (агрегаты + JOIN) -------
-- ФТ-11 · оператор · качество работы курьеров
SELECT c.full_name,
       COUNT(*)                        AS delivered_orders,
       AVG(o.delivered_at - o.paid_at) AS avg_delivery_time
FROM customer_order o
JOIN courier c ON c.courier_id = o.courier_id
WHERE o.status = 'delivered' AND o.delivered_at IS NOT NULL AND o.paid_at IS NOT NULL
GROUP BY c.courier_id, c.full_name
ORDER BY avg_delivery_time;

-- --- Q11 Клиенты с суммой оплаченных заказов выше средней (подзапрос)
-- ФТ-11 · оператор/маркетинг · выделить ценных клиентов
SELECT cu.full_name, SUM(p.amount) AS total_paid
FROM customer cu
JOIN customer_order o ON o.customer_id = cu.customer_id
JOIN payment p        ON p.order_id = o.order_id AND p.status = 'paid'
GROUP BY cu.customer_id, cu.full_name
HAVING SUM(p.amount) > (
    SELECT AVG(cust_total)
    FROM (
        SELECT SUM(p2.amount) AS cust_total
        FROM customer_order o2
        JOIN payment p2 ON p2.order_id = o2.order_id AND p2.status = 'paid'
        GROUP BY o2.customer_id
    ) s
)
ORDER BY total_paid DESC;

-- --- Q12 Доля отменённых заказов по ресторанам (условная агрегация) --
-- ФТ-11 · оператор · выявить рестораны с проблемами
SELECT r.name AS restaurant,
       COUNT(*)                                          AS total_orders,
       COUNT(*) FILTER (WHERE o.status = 'cancelled')    AS cancelled,
       ROUND(100.0 * COUNT(*) FILTER (WHERE o.status = 'cancelled')
             / COUNT(*), 1)                              AS cancelled_pct
FROM customer_order o
JOIN restaurant r ON r.restaurant_id = o.restaurant_id
GROUP BY r.restaurant_id, r.name
ORDER BY cancelled_pct DESC, restaurant;

-- --- Q14 Средний рейтинг ресторанов по отзывам (агрегаты + JOIN) -----
-- ФТ-12/ФТ-11 · клиент выбирает ресторан, оператор следит за качеством
-- [v1.3] отзыв привязан к заказу, ресторан получаем через JOIN (decisions.md №9)
SELECT r.name AS restaurant,
       ROUND(AVG(rv.restaurant_rating), 2) AS avg_rating,
       COUNT(*) AS reviews
FROM order_review rv
JOIN customer_order o ON o.order_id = rv.order_id
JOIN restaurant r     ON r.restaurant_id = o.restaurant_id
GROUP BY r.restaurant_id, r.name
ORDER BY avg_rating DESC, restaurant;


-- #####################################################################
-- ЧАСТЬ C. Транзакции (раздел 12 документа)
-- #####################################################################

-- --- T1: Оформление и оплата заказа (атомарно) ----------------------
<<<<<<< Updated upstream
-- Объединяем: создание заказа + позиции со снимком цен + проверку промокода
-- + оплату + перевод в 'paid'. Без транзакции: деньги списаны без заказа /
-- заказ без позиций / частичная вставка / сумма не совпадает со скидкой.
-- Параметры (psql -v): cust, rest, addr, promo_id, item1, q1, item2, q2, method.
-- Если промокода нет: promo_id=0.
BEGIN;

DROP TABLE IF EXISTS tmp_t1_items;
CREATE TEMP TABLE tmp_t1_items (
    item_id BIGINT NOT NULL,
    qty     INT    NOT NULL CHECK (qty > 0)
) ON COMMIT DROP;

INSERT INTO tmp_t1_items (item_id, qty)
VALUES (:item1, :q1), (:item2, :q2);

INSERT INTO customer_order (customer_id, restaurant_id, address_id, promo_id, status)
VALUES (:cust, :rest, :addr, NULLIF(:promo_id, 0), 'created')
=======
-- Объединяем: создание заказа + позиции со снимком цен + расчёт скидки по
-- промокоду (О19/О20) + оплата + перевод в 'paid'.
-- Без транзакции: деньги списаны без заказа / заказ без позиций / частичная вставка.
-- Параметры (psql -v): cust, rest, addr, item1, q1, item2, q2, method,
--   promo (id промокода или NULL).
-- Принцип отката: при любом нарушении (пустой заказ О11, невалидный промокод
-- О20) amount получается NULL → NOT NULL отбивает INSERT → вся транзакция
-- откатывается; непринимаемый способ оплаты (О24) отбивает составной FK (v4).
BEGIN;

INSERT INTO customer_order (customer_id, restaurant_id, address_id, promo_id, status)
VALUES (:cust, :rest, :addr, :promo, 'created')
>>>>>>> Stashed changes
RETURNING order_id \gset

-- позиции: цена берётся из меню СЕЙЧАС и фиксируется как unit_price
INSERT INTO order_item (order_id, item_id, restaurant_id, quantity, unit_price)
SELECT :order_id, mi.item_id, mi.restaurant_id, req.qty, mi.price
FROM tmp_t1_items req
JOIN menu_item mi ON mi.item_id = req.item_id
WHERE mi.restaurant_id = :rest AND mi.is_available;

<<<<<<< Updated upstream
-- Если хотя бы одна позиция не вставилась (чужой ресторан / недоступно),
-- промокод не найден/невалиден/сумма ниже минимума или метод оплаты не
-- принимается рестораном, amount станет NULL и INSERT упадёт по NOT NULL.
WITH requested AS (
    SELECT COUNT(*) AS requested_cnt FROM tmp_t1_items
),
inserted AS (
    SELECT COUNT(*) AS inserted_cnt,
           COALESCE(SUM(quantity * unit_price), 0)::NUMERIC(10,2) AS items_total
    FROM order_item
    WHERE order_id = :order_id
),
promo AS (
    SELECT *
    FROM promo_code
    WHERE promo_id = NULLIF(:promo_id, 0)
),
calc AS (
    SELECT CASE
        WHEN req.requested_cnt = 0 THEN NULL
        WHEN ins.inserted_cnt <> req.requested_cnt THEN NULL
        WHEN NOT EXISTS (
            SELECT 1
            FROM restaurant_payment_method rpm
            WHERE rpm.restaurant_id = :rest
              AND rpm.method = :'method'::payment_method
        ) THEN NULL
        WHEN NULLIF(:promo_id, 0) IS NOT NULL AND NOT EXISTS (
            SELECT 1
            FROM promo p
            WHERE current_date BETWEEN p.valid_from AND p.valid_to
              AND ins.items_total >= p.min_order_amount
        ) THEN NULL
        ELSE (
            ins.items_total - COALESCE((
                SELECT LEAST(
                    ins.items_total,
                    CASE p.discount_type
                        WHEN 'fixed' THEN p.discount_value
                        WHEN 'percent' THEN ROUND(ins.items_total * p.discount_value / 100, 2)
                    END
                )
                FROM promo p
                WHERE current_date BETWEEN p.valid_from AND p.valid_to
                  AND ins.items_total >= p.min_order_amount
            ), 0)
        )::NUMERIC(10,2)
    END AS amount
    FROM requested req CROSS JOIN inserted ins
)
INSERT INTO payment (order_id, restaurant_id, amount, method, status, paid_at)
SELECT :order_id, :rest, amount, :'method'::payment_method, 'paid', now()
FROM calc;
=======
-- [v1.4, Z2 рецензента] оплата = Σ позиций − скидка по промокоду (О19);
-- промокод применяется, только если действует по датам и сумма ≥ min_order_amount
-- (О20) — иначе d.discount IS NULL и CASE отдаёт NULL → откат всей транзакции.
INSERT INTO payment (order_id, restaurant_id, amount, method, status, paid_at)
SELECT :order_id, :rest,
       CASE WHEN :promo::bigint IS NULL OR d.discount IS NOT NULL
            THEN s.total - COALESCE(d.discount, 0)
       END,
       :'method'::payment_method, 'paid', now()
FROM (SELECT SUM(oi.quantity * oi.unit_price) AS total          -- NULL, если позиций нет (О11)
      FROM order_item oi WHERE oi.order_id = :order_id) s
LEFT JOIN LATERAL (
    SELECT LEAST(s.total, CASE pc.discount_type                  -- скидка не больше суммы
               WHEN 'fixed'   THEN pc.discount_value
               WHEN 'percent' THEN ROUND(s.total * pc.discount_value / 100.0, 2)
           END) AS discount
    FROM promo_code pc
    WHERE pc.promo_id = :promo
      AND CURRENT_DATE BETWEEN pc.valid_from AND pc.valid_to     -- О20: срок действия
      AND s.total >= pc.min_order_amount                         -- О20: минимальная сумма
) d ON true;
>>>>>>> Stashed changes

UPDATE customer_order
SET status = 'paid',
    paid_at = (SELECT paid_at FROM payment WHERE order_id = :order_id)
WHERE order_id = :order_id;

COMMIT;

-- --- T2: Отмена оплаченного заказа с возвратом (атомарно) ------------
-- ФТ-7. Без транзакции: статус 'cancelled', но деньги не возвращены.
-- [аудит 2026-06-10] добавлены стражи по статусу: О22 разрешает отмену только
-- НЕзавершённого заказа; прежняя версия молча отменяла и доставленный
-- (проверено на PG 18.4). Возврат выполняется только если отмена состоялась.
BEGIN;
    UPDATE customer_order SET status = 'cancelled'
    WHERE order_id = :order_id AND status NOT IN ('delivered', 'cancelled');
    UPDATE payment SET status = 'refunded'
    WHERE order_id = :order_id AND status = 'paid'
      AND EXISTS (SELECT 1 FROM customer_order o
                  WHERE o.order_id = :order_id AND o.status = 'cancelled');
COMMIT;
