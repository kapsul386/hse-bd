SET client_encoding TO 'UTF8';   -- файл в UTF-8; строка защищает от авто-WIN1252 на Windows
-- =====================================================================
-- SQL DML — запросы и транзакции   (проект «Перекус»)
-- Версия: v1 (проверено на PG 18 + seed.sql). Владелец: Роль 3.
-- Применение: psql -d perekus -f dml.sql   (после schema.sql + seed.sql)
-- Для КАЖДОГО запроса: ФТ / Кто / Зачем.  :param — psql-плейсхолдеры.
-- Покрытие: 7 запросов CRUD (Q1–Q7) + 5 сложных (Q8–Q12) + 2 транзакции.
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
-- ФТ-8 · клиент · список заказов с суммой и статусом
SELECT o.order_id, o.created_at, r.name AS restaurant, o.status,
       SUM(oi.quantity * oi.unit_price) AS items_total
FROM customer_order o
JOIN restaurant r  ON r.restaurant_id = o.restaurant_id
JOIN order_item oi ON oi.order_id = o.order_id
WHERE o.customer_id = :cust
GROUP BY o.order_id, o.created_at, r.name, o.status
ORDER BY o.created_at DESC;

-- --- Q5 (UPDATE) Изменение цены блюда -------------------------------
-- ФТ-9 · ресторан · меняет ТЕКУЩУЮ цену; снимки в прошлых заказах не затрагиваются
UPDATE menu_item SET price = :new_price WHERE item_id = :item;

-- --- Q6 (UPDATE) Назначить курьера и перевести заказ в доставку ------
-- ФТ-6 · оператор/курьер · назначение возможно только после оплаты/готовки
UPDATE customer_order
SET courier_id = :courier, status = 'on_the_way'
WHERE order_id = :order AND status IN ('paid', 'cooking');

-- --- Q7 (DELETE) Удалить НЕиспользуемый адрес клиента ----------------
-- ФТ-1 · клиент · удаляем адрес только если он не привязан ни к одному заказу
DELETE FROM address a
WHERE a.address_id = :addr
  AND NOT EXISTS (SELECT 1 FROM customer_order o WHERE o.address_id = a.address_id);


-- #####################################################################
-- ЧАСТЬ B. Сложные запросы — 5 штук
-- (JOIN / GROUP BY / подзапросы / агрегаты / оконные функции)
-- #####################################################################

-- --- Q8 Топ-5 блюд каждого ресторана по продажам (оконная) ----------
-- ФТ-10 · ресторан · что лучше всего продаётся
SELECT * FROM (
    SELECT r.name AS restaurant, mi.name AS item,
           SUM(oi.quantity) AS sold,
           ROW_NUMBER() OVER (PARTITION BY r.restaurant_id
                              ORDER BY SUM(oi.quantity) DESC) AS rnk
    FROM order_item oi
    JOIN menu_item mi ON mi.item_id = oi.item_id
    JOIN restaurant r ON r.restaurant_id = mi.restaurant_id
    GROUP BY r.restaurant_id, r.name, mi.item_id, mi.name
) t
WHERE rnk <= 5
ORDER BY restaurant, rnk;

-- --- Q9 Выручка по дням с нарастающим итогом (оконная) --------------
-- ФТ-10 · ресторан/оператор · динамика и накопленная выручка
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


-- #####################################################################
-- ЧАСТЬ C. Транзакции (раздел 12 документа)
-- #####################################################################

-- --- T1: Оформление и оплата заказа (атомарно) ----------------------
-- Объединяем: создание заказа + позиции со снимком цен + оплата + перевод в 'paid'.
-- Без транзакции: деньги списаны без заказа / заказ без позиций / частичная вставка.
BEGIN;

INSERT INTO customer_order (customer_id, restaurant_id, address_id, status)
VALUES (:cust, :rest, :addr, 'created')
RETURNING order_id \gset

-- позиции: цена берётся из меню СЕЙЧАС и фиксируется как unit_price
INSERT INTO order_item (order_id, item_id, restaurant_id, quantity, unit_price)
SELECT :order_id, mi.item_id, mi.restaurant_id, v.qty, mi.price
FROM menu_item mi
JOIN (VALUES (:item1, :q1), (:item2, :q2)) AS v(item_id, qty) ON v.item_id = mi.item_id
WHERE mi.restaurant_id = :rest AND mi.is_available;

-- оплата на сумму позиций (промокод/скидку добавить здесь же при наличии)
INSERT INTO payment (order_id, amount, method, status, paid_at)
SELECT :order_id, SUM(oi.quantity * oi.unit_price), 'card', 'paid', now()
FROM order_item oi WHERE oi.order_id = :order_id;

UPDATE customer_order SET status = 'paid', paid_at = now() WHERE order_id = :order_id;

COMMIT;

-- --- T2: Отмена оплаченного заказа с возвратом (атомарно) ------------
-- ФТ-7. Без транзакции: статус 'cancelled', но деньги не возвращены.
BEGIN;
    UPDATE customer_order SET status = 'cancelled' WHERE order_id = :order_id;
    UPDATE payment SET status = 'refunded' WHERE order_id = :order_id AND status = 'paid';
COMMIT;
