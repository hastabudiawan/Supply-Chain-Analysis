-- 0. Cek tipe data hasil impor (harus integer atau real, BUKAN text).
--    Jika ada yang text, impor ulang dan ubah Field type pada jendela impor.
SELECT typeof("Days for shipping (real)") AS tipe_days_real,
       typeof("Late_delivery_risk")       AS tipe_late,
       typeof("Order Profit Per Order")   AS tipe_profit
FROM dataco_raw LIMIT 1;

-- 1. Ukuran data mentah (harus: 180519 item, 65752 order, 20652 pelanggan)
SELECT COUNT(*) AS item,
       COUNT(DISTINCT "Order Id") AS orders,
       COUNT(DISTINCT "Customer Id") AS pelanggan
FROM dataco_raw;

-- 2. Status pengiriman per item di data mentah (Late delivery harus 98977 item)
SELECT "Delivery Status", COUNT(*) AS item
FROM dataco_raw
GROUP BY "Delivery Status"
ORDER BY item DESC;

-- 3. Apakah Late_delivery_risk identik dengan status "Late delivery"? (ya: hanya ada 4 baris hasil)
SELECT "Delivery Status", "Late_delivery_risk", COUNT(*) AS item
FROM dataco_raw
GROUP BY "Delivery Status", "Late_delivery_risk";

-- 4. Data pribadi: email dan password sudah disamarkan, tetapi kolom nama dan alamat tetap
--    tidak ikut tabel bersih
SELECT DISTINCT "Customer Email", "Customer Password" FROM dataco_raw;

-- 5. Kolom kosong (Order Zipcode harus 155679 kosong, Product Description 180519 kosong)
SELECT SUM(COALESCE(CAST("Order Zipcode" AS TEXT), '') = '')       AS order_zipcode_kosong,
       SUM(COALESCE(CAST("Product Description" AS TEXT), '') = '') AS product_description_kosong,
       COUNT(*) AS total
FROM dataco_raw;

-- 6. Kolom kembar: apakah "Sales per customer" sama dengan "Order Item Total"? (harus 100.0)
SELECT ROUND(AVG(ABS("Sales per customer" - "Order Item Total") < 0.01) * 100, 1) AS sama_pct
FROM dataco_raw;

-- 7. BUAT TABEL BERSIH (jalankan kedua pernyataan sekaligus, lalu Write Changes).
--    Hanya kolom yang dibutuhkan dipertahankan: data pribadi, kolom kembar, dan kolom kosong
--    tidak ikut. Tanggal teks (m/d/yyyy H:mm) diubah ke format YYYY-MM-DD.
CREATE TABLE supply_chain_item AS
SELECT
    "Order Id"                       AS order_id,
    "Order Item Id"                  AS order_item_id,
    "Customer Id"                    AS customer_id,
    substr(od, instr(od, ' ') - 4, 4) || '-'
      || printf('%02d', CAST(substr(od, 1, instr(od, '/') - 1) AS INTEGER)) || '-'
      || printf('%02d', CAST(substr(substr(od, instr(od, '/') + 1), 1,
                                    instr(substr(od, instr(od, '/') + 1), '/') - 1) AS INTEGER))
                                     AS order_date,
    "Shipping Mode"                  AS shipping_mode,
    "Days for shipment (scheduled)"  AS days_scheduled,
    "Days for shipping (real)"       AS days_real,
    "Days for shipping (real)" - "Days for shipment (scheduled)" AS gap,
    "Delivery Status"                AS delivery_status,
    "Late_delivery_risk"             AS late,
    "Order Status"                   AS order_status,
    "Type"                           AS payment_type,
    "Market"                         AS market,
    "Order Region"                   AS region,
    "Order Country"                  AS country,
    "Customer Segment"               AS segment,
    "Department Name"                AS department,
    "Category Name"                  AS category,
    "Product Name"                   AS product,
    "Order Item Quantity"            AS quantity,
    "Order Item Discount Rate"       AS discount_rate,
    "Sales"                          AS gross_sales,
    "Order Item Total"               AS net_sales,
    "Order Profit Per Order"         AS profit
FROM (SELECT *, "order date (DateOrders)" AS od FROM dataco_raw);

CREATE TABLE supply_chain_order AS
SELECT
    order_id,
    MIN(shipping_mode)   AS shipping_mode,
    MIN(days_scheduled)  AS days_scheduled,
    MIN(days_real)       AS days_real,
    MIN(gap)             AS gap,
    MIN(delivery_status) AS delivery_status,
    MIN(late)            AS late,
    MIN(order_status)    AS order_status,
    MIN(payment_type)    AS payment_type,
    MIN(market)          AS market,
    MIN(region)          AS region,
    MIN(country)         AS country,
    MIN(segment)         AS segment,
    MIN(order_date)      AS order_date,
    MIN(customer_id)     AS customer_id,
    COUNT(*)             AS items,
    SUM(net_sales)       AS net_sales,
    SUM(profit)          AS profit
FROM supply_chain_item
GROUP BY order_id;

-- 8. Validasi tabel bersih (harus: 180519, 65752, 54.82, 3966903)
SELECT (SELECT COUNT(*) FROM supply_chain_item)  AS item,
       (SELECT COUNT(*) FROM supply_chain_order) AS orders,
       (SELECT ROUND(AVG(late) * 100, 2) FROM supply_chain_order) AS terlambat_pct,
       (SELECT ROUND(SUM(profit)) FROM supply_chain_item) AS total_profit;

-- 9. Periode data (2015-01-01 sampai 2018-01-31)
SELECT MIN(order_date) AS awal, MAX(order_date) AS akhir,
       COUNT(DISTINCT customer_id) AS pelanggan
FROM supply_chain_order;

-- 10. Status pengiriman per order (terlambat harus 54.82%)
SELECT delivery_status, COUNT(*) AS orders,
       ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM supply_chain_order), 2) AS porsi_pct
FROM supply_chain_order
GROUP BY delivery_status
ORDER BY orders DESC;

-- 11. Rasio keterlambatan (54.82, tanpa batal 57.31, rata-rata keterlambatan 1.62 hari)
SELECT ROUND(AVG(late) * 100, 2) AS terlambat_pct,
       ROUND(AVG(CASE WHEN delivery_status <> 'Shipping canceled' THEN late END) * 100, 2) AS terlambat_tanpa_batal_pct,
       ROUND(AVG(CASE WHEN late = 1 THEN gap END), 2) AS rata_keterlambatan_hari
FROM supply_chain_order;

-- 12. Performa per shipping mode: janji vs aktual vs keterlambatan
SELECT shipping_mode,
       COUNT(*) AS orders,
       ROUND(AVG(days_scheduled), 2) AS janji_hari,
       ROUND(AVG(days_real), 2) AS aktual_hari,
       ROUND(AVG(late) * 100, 2) AS terlambat_pct,
       ROUND(AVG(CASE WHEN delivery_status <> 'Shipping canceled' THEN late END) * 100, 2) AS terlambat_tanpa_batal_pct
FROM supply_chain_order
GROUP BY shipping_mode
ORDER BY terlambat_pct DESC;

-- 13. Sebaran hari aktual per shipping mode (Second dan Standard Class tersebar merata 2-6 hari)
SELECT m.shipping_mode, m.days_real, m.orders,
       ROUND(m.orders * 100.0 / t.total, 1) AS pct_dalam_mode
FROM (SELECT shipping_mode, days_real, COUNT(*) AS orders
      FROM supply_chain_order GROUP BY shipping_mode, days_real) AS m
JOIN (SELECT shipping_mode, COUNT(*) AS total
      FROM supply_chain_order GROUP BY shipping_mode) AS t
  ON m.shipping_mode = t.shipping_mode
ORDER BY m.shipping_mode, m.days_real;

-- 14. Keterlambatan per market
SELECT market, COUNT(*) AS orders, ROUND(AVG(late) * 100, 2) AS terlambat_pct
FROM supply_chain_order
GROUP BY market
ORDER BY terlambat_pct;

-- 15. Keterlambatan per segmen pelanggan
SELECT segment, COUNT(*) AS orders, ROUND(AVG(late) * 100, 2) AS terlambat_pct
FROM supply_chain_order
GROUP BY segment
ORDER BY terlambat_pct;

-- 16. Keterlambatan per region (3 terendah; hapus LIMIT untuk semua region)
SELECT region, COUNT(*) AS orders, ROUND(AVG(late) * 100, 2) AS terlambat_pct
FROM supply_chain_order
GROUP BY region
ORDER BY terlambat_pct
LIMIT 3;

-- 17. Keterlambatan per tahun (2018 hanya Januari)
SELECT strftime('%Y', order_date) AS tahun, COUNT(*) AS orders, ROUND(AVG(late) * 100, 2) AS terlambat_pct
FROM supply_chain_order
GROUP BY tahun
ORDER BY tahun;

-- 18. Tren bulanan (37 bulan: 2015-01 sampai 2018-01)
SELECT strftime('%Y-%m', order_date) AS bulan, COUNT(*) AS orders, ROUND(AVG(late) * 100, 2) AS terlambat_pct
FROM supply_chain_order
GROUP BY bulan
ORDER BY bulan;

-- 19. Status order x tipe pembayaran (status ditentukan oleh tipe pembayaran)
SELECT order_status, payment_type, COUNT(*) AS orders
FROM supply_chain_order
GROUP BY order_status, payment_type
ORDER BY payment_type, orders DESC;

-- 20. Simulasi: persen terlambat jika jadwal diubah (tanpa order batal)
WITH jadwal(n) AS (VALUES (0), (1), (2), (3), (4), (5), (6)),
     asli AS (SELECT shipping_mode, MIN(days_scheduled) AS jadwal_asli
              FROM supply_chain_order GROUP BY shipping_mode)
SELECT o.shipping_mode, j.n AS jadwal_baru_hari,
       ROUND(AVG(o.days_real > j.n) * 100, 1) AS terlambat_pct
FROM supply_chain_order AS o
JOIN asli AS a ON a.shipping_mode = o.shipping_mode
JOIN jadwal AS j ON j.n >= a.jadwal_asli
WHERE o.delivery_status <> 'Shipping canceled'
GROUP BY o.shipping_mode, j.n
ORDER BY o.shipping_mode, j.n;

-- 21. Profit (level item): total, margin, dan baris berprofit negatif
SELECT ROUND(SUM(profit)) AS total_profit,
       ROUND(SUM(net_sales)) AS net_sales,
       ROUND(SUM(profit) * 100.0 / SUM(net_sales), 2) AS margin_pct,
       SUM(profit < 0) AS item_profit_negatif,
       ROUND(AVG(profit < 0) * 100, 1) AS profit_negatif_pct
FROM supply_chain_item;

-- 22. Profit per status pengiriman
SELECT delivery_status, COUNT(*) AS item,
       ROUND(AVG(profit), 2) AS rata_profit, ROUND(SUM(profit)) AS total_profit
FROM supply_chain_item
GROUP BY delivery_status
ORDER BY rata_profit DESC;

-- 23. Departemen dengan porsi profit negatif tertinggi
SELECT department, COUNT(*) AS item,
       ROUND(AVG(profit < 0) * 100, 1) AS profit_negatif_pct,
       ROUND(SUM(profit)) AS total_profit
FROM supply_chain_item
GROUP BY department
ORDER BY profit_negatif_pct DESC
LIMIT 4;

-- 24. Sebaran keterlambatan pada order terlambat (hari)
SELECT gap AS terlambat_hari, COUNT(*) AS orders
FROM supply_chain_order
WHERE late = 1
GROUP BY gap
ORDER BY gap;