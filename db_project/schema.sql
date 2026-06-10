SET client_encoding TO 'UTF8';   -- файл в UTF-8; строка защищает от авто-WIN1252 на Windows
-- =====================================================================
-- КАНОНИЧЕСКАЯ СХЕМА БД  (единый источник правды)
-- Проект: «Перекус» — доставка еды (маркетплейс)
-- Версия: v1 (каноническая, проверена на PostgreSQL 18). Schema freeze — правит только Роль 1.
-- Применение: psql -d perekus -f schema.sql
-- =====================================================================

-- --- чистый старт (удобно при пересборке) ----------------------------
DROP TABLE IF EXISTS payment, order_item, customer_order, promo_code,
    menu_item, menu_category, restaurant_payment_method, restaurant_cuisine,
    cuisine, restaurant, address, courier, customer CASCADE;
DROP TYPE IF EXISTS order_status, payment_method, payment_status, discount_type CASCADE;

-- ---------------------------------------------------------------------
-- 0. Перечислимые типы
-- ---------------------------------------------------------------------
CREATE TYPE order_status   AS ENUM ('created','paid','cooking','on_the_way','delivered','cancelled');
CREATE TYPE payment_method AS ENUM ('card','cash','sbp');
CREATE TYPE payment_status AS ENUM ('pending','paid','refunded');
CREATE TYPE discount_type  AS ENUM ('percent','fixed');

-- ---------------------------------------------------------------------
-- 1. Клиенты и адреса
-- ---------------------------------------------------------------------
CREATE TABLE customer (
    customer_id  BIGSERIAL PRIMARY KEY,
    full_name    TEXT        NOT NULL,
    phone        TEXT        NOT NULL UNIQUE,
    email        TEXT,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE address (
    address_id   BIGSERIAL PRIMARY KEY,
    customer_id  BIGINT NOT NULL REFERENCES customer(customer_id) ON DELETE CASCADE,
    city         TEXT NOT NULL,
    street       TEXT NOT NULL,
    building     TEXT NOT NULL,
    apartment    TEXT,
    comment      TEXT
);

-- ---------------------------------------------------------------------
-- 2. Рестораны, кухни, принимаемые способы оплаты (4НФ-разнесение)
-- ---------------------------------------------------------------------
CREATE TABLE restaurant (
    restaurant_id BIGSERIAL PRIMARY KEY,
    name          TEXT NOT NULL,
    phone         TEXT NOT NULL,
    address_text  TEXT NOT NULL,
    is_active     BOOLEAN NOT NULL DEFAULT true
);

CREATE TABLE cuisine (
    cuisine_id  SERIAL PRIMARY KEY,
    name        TEXT NOT NULL UNIQUE          -- «Итальянская», «Японская» …
);

-- независимый многозначный факт №1: какие кухни у ресторана
CREATE TABLE restaurant_cuisine (
    restaurant_id BIGINT NOT NULL REFERENCES restaurant(restaurant_id) ON DELETE CASCADE,
    cuisine_id    INT    NOT NULL REFERENCES cuisine(cuisine_id),
    PRIMARY KEY (restaurant_id, cuisine_id)
);

-- независимый многозначный факт №2: какие способы оплаты принимает ресторан
CREATE TABLE restaurant_payment_method (
    restaurant_id BIGINT         NOT NULL REFERENCES restaurant(restaurant_id) ON DELETE CASCADE,
    method        payment_method NOT NULL,
    PRIMARY KEY (restaurant_id, method)
);

-- ---------------------------------------------------------------------
-- 3. Меню
-- ---------------------------------------------------------------------
CREATE TABLE menu_category (
    category_id   BIGSERIAL PRIMARY KEY,
    restaurant_id BIGINT NOT NULL REFERENCES restaurant(restaurant_id) ON DELETE CASCADE,
    name          TEXT NOT NULL,
    UNIQUE (restaurant_id, name)
);

CREATE TABLE menu_item (
    item_id       BIGSERIAL PRIMARY KEY,
    restaurant_id BIGINT NOT NULL REFERENCES restaurant(restaurant_id) ON DELETE CASCADE,
    category_id   BIGINT NOT NULL REFERENCES menu_category(category_id),
    name          TEXT NOT NULL,
    description   TEXT,
    price         NUMERIC(10,2) NOT NULL CHECK (price >= 0),   -- ТЕКУЩАЯ цена
    is_available  BOOLEAN NOT NULL DEFAULT true,
    -- нужно для составного FK из order_item (ограничение «позиции того же ресторана»)
    UNIQUE (item_id, restaurant_id)
);

-- ---------------------------------------------------------------------
-- 4. Курьеры и промокоды
-- ---------------------------------------------------------------------
CREATE TABLE courier (
    courier_id   BIGSERIAL PRIMARY KEY,
    full_name    TEXT NOT NULL,
    phone        TEXT NOT NULL UNIQUE,
    vehicle_type TEXT,
    is_active    BOOLEAN NOT NULL DEFAULT true
);

CREATE TABLE promo_code (
    promo_id         BIGSERIAL PRIMARY KEY,
    code             TEXT NOT NULL UNIQUE,
    discount_type    discount_type NOT NULL,
    discount_value   NUMERIC(10,2) NOT NULL CHECK (discount_value >= 0),
    min_order_amount NUMERIC(10,2) NOT NULL DEFAULT 0,
    valid_from       DATE NOT NULL,
    valid_to         DATE NOT NULL,
    CHECK (valid_to >= valid_from)
);

-- ---------------------------------------------------------------------
-- 5. Заказы
-- ---------------------------------------------------------------------
CREATE TABLE customer_order (
    order_id      BIGSERIAL PRIMARY KEY,
    customer_id   BIGINT NOT NULL REFERENCES customer(customer_id),
    restaurant_id BIGINT NOT NULL REFERENCES restaurant(restaurant_id),
    address_id    BIGINT NOT NULL REFERENCES address(address_id),
    courier_id    BIGINT REFERENCES courier(courier_id),       -- NULL до назначения
    promo_id      BIGINT REFERENCES promo_code(promo_id),      -- NULL если без промокода
    status        order_status NOT NULL DEFAULT 'created',
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    paid_at       TIMESTAMPTZ,
    delivered_at  TIMESTAMPTZ,
    -- нужно как цель составного FK из order_item
    UNIQUE (order_id, restaurant_id)
);

CREATE TABLE order_item (
    order_id      BIGINT NOT NULL,
    item_id       BIGINT NOT NULL,
    restaurant_id BIGINT NOT NULL,
    quantity      INT NOT NULL CHECK (quantity > 0),
    unit_price    NUMERIC(10,2) NOT NULL CHECK (unit_price >= 0),  -- СНИМОК цены на момент заказа
    PRIMARY KEY (order_id, item_id),
    -- позиция принадлежит этому заказу:
    FOREIGN KEY (order_id, restaurant_id) REFERENCES customer_order(order_id, restaurant_id) ON DELETE CASCADE,
    -- ...и блюдо — из ресторана этого заказа (декларативно реализует ограничение №2 из раздела 6):
    FOREIGN KEY (item_id, restaurant_id)  REFERENCES menu_item(item_id, restaurant_id)
);

CREATE TABLE payment (
    payment_id BIGSERIAL PRIMARY KEY,
    order_id   BIGINT NOT NULL UNIQUE REFERENCES customer_order(order_id) ON DELETE CASCADE, -- 1:1
    amount     NUMERIC(10,2) NOT NULL CHECK (amount >= 0),
    method     payment_method NOT NULL,
    status     payment_status NOT NULL DEFAULT 'pending',
    paid_at    TIMESTAMPTZ
);

-- ---------------------------------------------------------------------
-- 6. Индексы под частые/аналитические запросы (раздел 4 НФТ, рубрика №7)
-- ---------------------------------------------------------------------
CREATE INDEX idx_order_customer    ON customer_order (customer_id);
CREATE INDEX idx_order_restaurant  ON customer_order (restaurant_id);
CREATE INDEX idx_order_courier     ON customer_order (courier_id);
CREATE INDEX idx_order_created     ON customer_order (created_at);
CREATE INDEX idx_orderitem_item    ON order_item (item_id);
CREATE INDEX idx_menuitem_rest_cat ON menu_item (restaurant_id, category_id);
