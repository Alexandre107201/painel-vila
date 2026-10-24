-- DRAFT: execute first in an isolated staging database, never automatically.
BEGIN;
CREATE TABLE public.hands_cmv_captures (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 operation text NOT NULL CHECK (operation = 'Vila Fit / Vila Gourmet'),
 competence date NOT NULL CHECK (extract(day from competence) = 1),
 cmv_percent numeric(5,2) NOT NULL CHECK (cmv_percent BETWEEN 0 AND 100),
 merchandise_cost numeric(16,2) NOT NULL CHECK (merchandise_cost >= 0),
 sales_revenue numeric(16,2) NOT NULL CHECK (sales_revenue > 0),
 captured_at timestamptz NOT NULL,
 received_at timestamptz NOT NULL DEFAULT now(),
 CHECK (abs(merchandise_cost / sales_revenue * 100 - cmv_percent) <= 0.02),
 CHECK (captured_at BETWEEN received_at - interval '10 minutes' AND received_at + interval '1 minute')
);
CREATE INDEX hands_cmv_latest ON public.hands_cmv_captures(operation, competence, captured_at DESC);
ALTER TABLE public.hands_cmv_captures ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.hands_cmv_captures FROM PUBLIC, anon, authenticated;
-- Only the two existing manual-import administrators may read this indicator.
-- No new public access, and no SELECT access to cost/revenue amounts.
GRANT SELECT(operation, competence, cmv_percent, captured_at, received_at)
 ON public.hands_cmv_captures TO authenticated;
GRANT INSERT(operation, competence, cmv_percent, merchandise_cost, sales_revenue, captured_at)
 ON public.hands_cmv_captures TO authenticated;
CREATE POLICY hands_cmv_admin_read ON public.hands_cmv_captures FOR SELECT TO authenticated
 USING ((SELECT auth.uid()) IN ('21d9a9d4-022d-4c24-a26a-cc7af788aa2a'::uuid,
                              '0be7c2a3-0f8f-4538-a476-d9900b4e0f2a'::uuid));
-- Dedicated Auth user: app_metadata set only by an administrator, never user_metadata.
CREATE POLICY hands_cmv_writer_insert ON public.hands_cmv_captures FOR INSERT TO authenticated
 WITH CHECK ((SELECT auth.jwt()->'app_metadata'->>'hands_cmv_writer') = 'true'
  AND competence = date_trunc('month', now() AT TIME ZONE 'America/Sao_Paulo')::date
  AND captured_at BETWEEN now() - interval '10 minutes' AND now() + interval '1 minute');
COMMIT;
