SET client_encoding TO 'UTF8';   -- файл в UTF-8; строка защищает от авто-WIN1252 на Windows
-- =====================================================================
-- ТЕСТОВЫЕ ДАННЫЕ (seed)   проект «Перекус»
-- Версия: v1.0 (финальная тестовая выборка под schema.sql v4). Применять ПОСЛЕ schema.sql:
--   psql -d perekus -f schema.sql
--   psql -d perekus -f seed.sql
-- Идемпотентно: TRUNCATE в начале — можно прогонять повторно.
--
-- Данные подобраны так, чтобы сложные запросы из dml.sql были осмысленны:
--   * заказы за 5 разных дней (нарастающий итог выручки),
--   * у каждого курьера ≥2 доставки (среднее время доставки),
--   * у блюд разные объёмы продаж (топ-N по ресторанам),
--   * есть отменённый (refunded) и ещё не доставленный (cooking) заказы,
--   * отзывы только на часть доставленных заказов (средний рейтинг, Q14).
-- ДЕМО СНИМКА ЦЕНЫ: «Маргарита» сейчас стоит 550, но в заказе №1 от 01.06
--   зафиксирована старая цена 500 — история не искажается при росте цены.
-- =====================================================================

TRUNCATE order_review, payment, order_item, customer_order, promo_code, menu_item,
    menu_category, restaurant_payment_method, restaurant_cuisine, cuisine,
    restaurant, address, courier, customer RESTART IDENTITY CASCADE;

BEGIN;

-- 1. Клиенты ----------------------------------------------------------
INSERT INTO customer (customer_id, full_name, phone, email, created_at) VALUES
 (1,'Анна Иванова',      '+7-900-000-0001','anna@example.com', '2025-12-01'),
 (2,'Борис Петров',      '+7-900-000-0002','boris@example.com','2025-12-05'),
 (3,'Виктория Смирнова', '+7-900-000-0003','vika@example.com', '2026-01-10'),
 (4,'Геннадий Кузнецов', '+7-900-000-0004', NULL,              '2026-02-20'),
 (5,'Дарья Соколова',    '+7-900-000-0005','daria@example.com','2026-03-15');

-- 2. Адреса (у Анны их два) -------------------------------------------
INSERT INTO address (address_id, customer_id, city, street, building, apartment, comment) VALUES
 (1,1,'Москва','ул. Тверская','10','5',  NULL),
 (2,1,'Москва','ул. Арбат',   '20','12', 'код 12К'),
 (3,2,'Москва','ул. Ленина',  '3', '7',  NULL),
 (4,3,'Москва','ул. Мира',    '15','2',  NULL),
 (5,4,'Москва','ул. Победы',  '8', '44', 'домофон'),
 (6,5,'Москва','ул. Садовая', '1', '9',  NULL);

-- 3. Рестораны --------------------------------------------------------
INSERT INTO restaurant (restaurant_id, name, phone, address_text, is_active) VALUES
 (1,'Пицца Рома', '+7-495-100-1001','Москва, ул. Тверская, 1',true),
 (2,'Суши Кит',   '+7-495-100-1002','Москва, ул. Арбат, 12',  true),
 (3,'Бургер Хаус','+7-495-100-1003','Москва, пр. Мира, 30',   true);

-- 4. Кухни и связи M:N ------------------------------------------------
INSERT INTO cuisine (cuisine_id, name) VALUES
 (1,'Итальянская'),(2,'Японская'),(3,'Американская'),(4,'Фастфуд');

INSERT INTO restaurant_cuisine (restaurant_id, cuisine_id) VALUES
 (1,1),(2,2),(3,3),(3,4);            -- Бургер Хаус: 2 кухни

-- независимо от кухонь — принимаемые способы оплаты (демо 4НФ)
INSERT INTO restaurant_payment_method (restaurant_id, method) VALUES
 (1,'card'),(1,'sbp'),
 (2,'card'),(2,'cash'),
 (3,'card'),(3,'cash'),(3,'sbp');

-- 5. Меню -------------------------------------------------------------
INSERT INTO menu_category (category_id, restaurant_id, name) VALUES
 (1,1,'Пицца'),(2,1,'Напитки'),
 (3,2,'Роллы'),(4,2,'Напитки'),
 (5,3,'Бургеры'),(6,3,'Закуски');

INSERT INTO menu_item (item_id, restaurant_id, category_id, name, description, price, is_available) VALUES
 (1, 1,1,'Маргарита',     'Томаты, моцарелла, базилик',          550.00,true),
 (2, 1,1,'Пепперони',     'Пикантная пепперони, сыр',            650.00,true),
 (3, 1,1,'Четыре сыра',   'Моцарелла, горгонзола, пармезан',     700.00,true),
 (4, 1,2,'Кола 0.5',      NULL,                                  120.00,true),
 (5, 2,3,'Филадельфия',   'Лосось, сливочный сыр',               480.00,true),
 (6, 2,3,'Калифорния',    'Краб, авокадо, икра тобико',          420.00,true),
 (7, 2,4,'Зелёный чай',   NULL,                                  150.00,true),
 (8, 2,3,'Унаги маки',    'Копчёный угорь',                      390.00,true),
 (9, 3,5,'Чизбургер',     'Говядина, чеддер',                    320.00,true),
 (10,3,5,'Двойной бекон', 'Двойная котлета, бекон',              450.00,true),
 (11,3,6,'Картошка фри',  NULL,                                  180.00,true),
 (12,3,6,'Луковые кольца','Временно недоступно',                 200.00,false); -- недоступно

-- 6. Курьеры ----------------------------------------------------------
INSERT INTO courier (courier_id, full_name, phone, vehicle_type, is_active) VALUES
 (1,'Иван Курьеров',  '+7-900-111-0001','bike',   true),
 (2,'Олег Быстров',   '+7-900-111-0002','car',    true),
 (3,'Сергей Лётчиков','+7-900-111-0003','scooter',true);

-- 7. Промокоды --------------------------------------------------------
INSERT INTO promo_code (promo_id, code, discount_type, discount_value, min_order_amount, valid_from, valid_to) VALUES
 (1,'WELCOME200','fixed',  200.00, 800.00,'2025-01-01','2026-12-31'),
 (2,'SUSHI10',   'percent', 10.00, 500.00,'2025-01-01','2026-12-31');

-- 8. Заказы (5 дней, разные статусы/курьеры) --------------------------
INSERT INTO customer_order
 (order_id, customer_id, restaurant_id, address_id, courier_id, promo_id, status, created_at, paid_at, delivered_at) VALUES
 (1,1,1,1,1,NULL,  'delivered','2026-06-01 12:00','2026-06-01 12:05','2026-06-01 12:45'),
 (2,2,1,3,2,1,     'delivered','2026-06-01 13:00','2026-06-01 13:05','2026-06-01 13:50'),
 (3,3,2,4,1,2,     'delivered','2026-06-02 19:00','2026-06-02 19:03','2026-06-02 19:40'),
 (4,4,2,5,3,NULL,  'delivered','2026-06-02 20:00','2026-06-02 20:04','2026-06-02 20:55'),
 (5,1,3,2,2,NULL,  'delivered','2026-06-03 14:00','2026-06-03 14:02','2026-06-03 14:35'),
 (6,5,3,6,1,NULL,  'delivered','2026-06-03 18:30','2026-06-03 18:33','2026-06-03 19:10'),
 (7,2,1,3,3,NULL,  'delivered','2026-06-04 12:30','2026-06-04 12:33','2026-06-04 13:05'),
 (8,3,2,4,NULL,NULL,'cancelled','2026-06-04 21:00','2026-06-04 21:02',NULL),
 (9,4,1,5,NULL,NULL,'cooking',  '2026-06-05 11:00','2026-06-05 11:02',NULL);

-- 9. Позиции заказов (restaurant_id = ресторан заказа = ресторан блюда)
--    unit_price — СНИМОК цены на момент заказа.
INSERT INTO order_item (order_id, item_id, restaurant_id, quantity, unit_price) VALUES
 (1, 1,1,3,500.00),   -- старая цена Маргариты (сейчас в меню 550)
 (1, 4,1,1,120.00),
 (2, 2,1,2,650.00),(2, 3,1,1,700.00),(2, 4,1,1,120.00),
 (3, 5,2,2,480.00),(3, 7,2,1,150.00),
 (4, 6,2,3,420.00),(4, 5,2,1,480.00),
 (5, 9,3,2,320.00),(5,11,3,2,180.00),
 (6,10,3,1,450.00),(6, 9,3,1,320.00),(6,11,3,1,180.00),
 (7, 1,1,2,550.00),(7, 2,1,1,650.00),   -- новая цена Маргариты
 (8, 5,2,1,480.00),(8, 8,2,1,390.00),
 (9, 3,1,2,700.00);

-- 10. Оплаты (1:1 к заказу; суммы согласованы с позициями и скидками;
--     restaurant_id = ресторану заказа, method ∈ принимаемых рестораном — v4, О24)
INSERT INTO payment (payment_id, order_id, restaurant_id, amount, method, status, paid_at) VALUES
 (1,1,1,1620.00,'card','paid',    '2026-06-01 12:05'),
 (2,2,1,1920.00,'sbp', 'paid',    '2026-06-01 13:05'),  -- 2120 − 200 (WELCOME200)
 (3,3,2, 999.00,'card','paid',    '2026-06-02 19:03'),  -- 1110 − 10% (SUSHI10)
 (4,4,2,1740.00,'cash','paid',    '2026-06-02 20:04'),
 (5,5,3,1000.00,'card','paid',    '2026-06-03 14:02'),
 (6,6,3, 950.00,'sbp', 'paid',    '2026-06-03 18:33'),
 (7,7,1,1750.00,'card','paid',    '2026-06-04 12:33'),
 (8,8,2, 870.00,'card','refunded','2026-06-04 21:02'),  -- отменён → возврат
 (9,9,1,1400.00,'card','paid',    '2026-06-05 11:02');

-- 10b. Отзывы (ФТ-12): только на ДОСТАВЛЕННЫЕ заказы, created_at >= delivered_at;
--      заказ 6 — без оценки курьера (courier_rating NULL допустим).
INSERT INTO order_review (review_id, order_id, restaurant_rating, courier_rating, comment, created_at) VALUES
 (1,1,5,5,'Быстро и горячо',  '2026-06-01 13:10'),
 (2,2,4,4,NULL,               '2026-06-01 14:30'),
 (3,3,5,4,'Роллы свежие',     '2026-06-02 20:15'),
 (4,5,3,5,'Бургер остыл',     '2026-06-03 15:20'),
 (5,6,4,NULL,'Доставка ок',   '2026-06-03 19:40');

COMMIT;

-- 11. Синхронизация последовательностей с явными ID -------------------
SELECT setval(pg_get_serial_sequence('customer','customer_id'),             (SELECT MAX(customer_id)   FROM customer));
SELECT setval(pg_get_serial_sequence('address','address_id'),               (SELECT MAX(address_id)    FROM address));
SELECT setval(pg_get_serial_sequence('restaurant','restaurant_id'),         (SELECT MAX(restaurant_id) FROM restaurant));
SELECT setval(pg_get_serial_sequence('cuisine','cuisine_id'),               (SELECT MAX(cuisine_id)    FROM cuisine));
SELECT setval(pg_get_serial_sequence('menu_category','category_id'),        (SELECT MAX(category_id)   FROM menu_category));
SELECT setval(pg_get_serial_sequence('menu_item','item_id'),                (SELECT MAX(item_id)       FROM menu_item));
SELECT setval(pg_get_serial_sequence('courier','courier_id'),               (SELECT MAX(courier_id)    FROM courier));
SELECT setval(pg_get_serial_sequence('promo_code','promo_id'),              (SELECT MAX(promo_id)      FROM promo_code));
SELECT setval(pg_get_serial_sequence('customer_order','order_id'),          (SELECT MAX(order_id)      FROM customer_order));
SELECT setval(pg_get_serial_sequence('payment','payment_id'),               (SELECT MAX(payment_id)    FROM payment));
SELECT setval(pg_get_serial_sequence('order_review','review_id'),           (SELECT MAX(review_id)     FROM order_review));

-- 12. Быстрая проверка загрузки --------------------------------------
SELECT 'customer' AS tbl, COUNT(*) FROM customer
UNION ALL SELECT 'restaurant', COUNT(*) FROM restaurant
UNION ALL SELECT 'menu_item',  COUNT(*) FROM menu_item
UNION ALL SELECT 'order',      COUNT(*) FROM customer_order
UNION ALL SELECT 'order_item', COUNT(*) FROM order_item
UNION ALL SELECT 'payment',    COUNT(*) FROM payment
UNION ALL SELECT 'review',     COUNT(*) FROM order_review;
