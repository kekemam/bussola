// ============================================================
// BÚSSOLA · comprar-destaque
//
// Porta de pagamento do único ponto de receita da plataforma.
// A função `comprar_destaque()` na base de dados é executável apenas
// pelo service_role, precisamente para que ninguém possa oferecer-se
// destaques chamando a API REST. Esta função é a única entrada.
//
// Faz três coisas, por esta ordem:
//   1. confirma que quem pede é membro da empresa dona do anúncio
//   2. cobra
//   3. só depois grava o destaque
//
// Sem fornecedor de pagamento configurado, recusa. Não concede
// destaques grátis por omissão — seria reabrir o buraco que o
// RLS fecha, uma camada acima.
// ============================================================
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: unknown, s = 200) =>
  new Response(JSON.stringify(b), { status: s, headers: { ...cors, "Content-Type": "application/json" } });

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ erro: "metodo_nao_permitido" }, 405);

  try {
    const body = await req.json().catch(() => null);
    const listingId = String(body?.listing_id ?? "").trim();
    const packageId = String(body?.package_id ?? "").trim();
    if (!listingId || !packageId) return json({ erro: "parametros_em_falta" }, 400);

    // ---- 1. quem está a pedir ----
    const token = (req.headers.get("Authorization") ?? "").replace("Bearer ", "").trim();
    if (!token) return json({ erro: "sem_sessao" }, 401);

    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const { data: auth } = await admin.auth.getUser(token);
    const userId = auth?.user?.id;
    if (!userId) return json({ erro: "sessao_invalida" }, 401);

    // ---- 2. o anúncio é mesmo da empresa dele? ----
    const { data: listing } = await admin
      .from("listings")
      .select("id, company_id, title")
      .eq("id", listingId)
      .maybeSingle();
    if (!listing) return json({ erro: "anuncio_inexistente" }, 404);

    const { data: membro } = await admin
      .from("company_members")
      .select("user_id")
      .eq("company_id", listing.company_id)
      .eq("user_id", userId)
      .maybeSingle();
    if (!membro) return json({ erro: "sem_permissao_neste_anuncio" }, 403);

    // ---- 3. quanto custa (o preço vem da BD, nunca do cliente) ----
    const { data: pacote } = await admin
      .from("boost_packages")
      .select("id, name, days, price_cents")
      .eq("id", packageId)
      .eq("active", true)
      .maybeSingle();
    if (!pacote) return json({ erro: "pacote_invalido" }, 400);

    // ---- 4. cobrar ----
    const stripeKey = Deno.env.get("STRIPE_SECRET_KEY");
    const demo = Deno.env.get("DEMO_BOOSTS") === "1";

    let paymentRef: string;
    if (stripeKey) {
      // Integração real a implementar: criar PaymentIntent e confirmar
      // antes de gravar. Enquanto não existir, não se concede destaque.
      return json({
        erro: "pagamento_por_implementar",
        mensagem: "O fornecedor de pagamento está configurado mas a integração ainda não está feita.",
      }, 501);
    } else if (demo) {
      // Modo de demonstração: ligado explicitamente pelo dono do projeto
      // através do segredo DEMO_BOOSTS=1. Nunca é o comportamento padrão.
      paymentRef = "demo-" + crypto.randomUUID();
    } else {
      return json({
        erro: "pagamento_nao_configurado",
        mensagem: "Não é possível comprar destaques sem um método de pagamento configurado.",
      }, 503);
    }

    // ---- 5. gravar ----
    const { data: boost, error } = await admin.rpc("comprar_destaque", {
      p_listing: listingId,
      p_package: packageId,
      p_payment_ref: paymentRef,
    });
    if (error) {
      console.error("comprar_destaque_falhou", error.message);
      return json({ erro: "falha_ao_gravar", mensagem: error.message }, 500);
    }

    return json({
      ok: true,
      destaque: boost,
      pacote: { id: pacote.id, nome: pacote.name, dias: pacote.days, preco_cents: pacote.price_cents },
      demo: !stripeKey,
    });
  } catch (e) {
    console.error("erro_inesperado", e);
    return json({ erro: "erro_interno" }, 500);
  }
});
