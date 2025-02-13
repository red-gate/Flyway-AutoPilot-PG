CREATE OR REPLACE VIEW sales.customer_orders_view (customer_id, first_name, last_name, order_id, order_date, status, total_amount) AS SELECT c.customer_id,
    c.first_name,
    c.last_name,
    o.order_id,
    o.order_date,
    o.status,
    o.total_amount,
    o.ticket_quantity
   FROM customers.customer c
     JOIN sales.orders o ON c.customer_id = o.customer_id;