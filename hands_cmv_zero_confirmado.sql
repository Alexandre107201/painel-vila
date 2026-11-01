BEGIN;
-- Regras anteriores: sales_revenue > 0 e verificacao direta costs/revenue.
-- Zero somente quando receita, custo e percentual forem todos zero.
ALTER TABLE public.hands_cmv_captures DROP CONSTRAINT hands_cmv_captures_sales_revenue_check;
ALTER TABLE public.hands_cmv_captures DROP CONSTRAINT hands_cmv_captures_check;
ALTER TABLE public.hands_cmv_captures
 ADD CONSTRAINT hands_cmv_captures_sales_revenue_check CHECK (sales_revenue>=0),
 ADD CONSTRAINT hands_cmv_captures_check CHECK (
 CASE WHEN sales_revenue=0 THEN merchandise_cost=0 AND cmv_percent=0
      WHEN sales_revenue>0 THEN abs(merchandise_cost/sales_revenue*100-cmv_percent)<=0.02
      ELSE false END
 );
COMMIT;