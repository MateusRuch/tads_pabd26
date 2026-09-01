-- Views

-- No psql: \dv - visualiar as views existentes
-- No psql: \d+ v_users_orders - visualizar detalhes da view.

--1. Resumo de pedidos por usuário()
drop view if exists v_users_orders;
create view v_users_orders as -- criação da view para não precisar realizando o mesmo código a todo momento
select
    u.id id,
    u.name usuario, 
    count (o.id) qtd_pedidos,
    coalesce(sum(o.total), 0) total_gasto
from users u
left join orders o on o.user_id = u.user_id
group by u.id, u.name;

-- select * from v_users_orders order by id;

-- 2. Relatório de vendas de produtos(id, produto, qtd_vendida, totaL_vendido:
drop view if exists v_products_sales;
create view v_products_sales as
SELECT 
    p.id id,
    p.name produto,
    sum(op.quantity) qtd_vendida,
    sum(op.quantity * op.unit_price) total_vendido
from products p
join orders_products op on product_id = p.id
join orders o on o.id = op.order_id
where o.status <> 'canceled'
GROUP BY p.id, p.name;

-- select * from v_products_sales orer by id;



-- 3. Relatório detalhado de pedidos:
drop view if exists v_orders_details;
create view v_orders_details as 
select
    o.id id,
    u.name usuario,
    u.email email,
    o.order_date,
    o.status,
    p.name produto,
    op.quantity qtd,
    op.unit_price valor_unitario,
    op.unit_price * op.quantity valor_total
from orders o
join users u on u.id = o.user_id
join orders_products op on op.order_id = o.id
join products p on p.id = op.product_id;

-- select * from v_orders_details order by id;

-- 4. Relatório de itens em estoque

drop view if exists v_products_in_stock;
create view v_products_in_stock as 
select 
    id,
    name produto,
    price valor,
    stock estoque
from products
where stock > 0
with CHECK OPTION; 

-- select * from v_products_in_stock;

update v_products_in_stock
set estoque = 0
where id = 1
returning id,produto,estoque;

