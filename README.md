# Bússola

**Onde Portugal começa a fazer sentido.**

Plataforma de integração para pessoas dos países PALOP — Angola 🇦🇴, Cabo Verde 🇨🇻, Guiné-Bissau 🇬🇼, Moçambique 🇲🇿 e São Tomé e Príncipe 🇸🇹 — que chegam ou já vivem em Portugal.

Transforma uma experiência normalmente confusa (documentação, casa, trabalho, direitos) num plano organizado, passo a passo.

---

## Superfícies

Site estático, sem framework e sem passo de build. O `vercel.json` faz o routing.

| Rota | Ficheiro | O que é |
|---|---|---|
| `/` | `index.html` | Landing de marketing |
| `/app` | `app.html` | App do utilizador |
| `/painel` | `painel.html` | Painéis de profissional, empresa, imobiliária e organizador |
| `/admin` | `admin.html` | Consola de administração |

Cada ficheiro é **autónomo**: CSS, HTML e JS vanilla num só. Não converter para framework sem pedido explícito.

---

## Design system

- **Papel quente** `#F7F4EF` · **tinta** `#1C1A16` · acento **terracota** `#C25A3A` · apoio **sage** `#3E6B5A`
- Tipografia: **Fraunces** (títulos) + **Inter** (corpo)
- Tema claro e escuro em todas as superfícies
- Mobile tem navegação própria (bottom-nav), não é uma versão reduzida do desktop

### Convenções

- **Português europeu**, sempre. Nunca brasileiro: *arrendamento* (não aluguel), *ficheiro* (não arquivo), *candidatura* (não aplicação), *contacto* (não contato).
- Ícones via `svg(nome)`, com a classe base `.i`.
- **Não** usar `${var}1a` para alfa em variáveis CSS — usar `color-mix()`.
- Validar a sintaxe JS antes de cada commit:

```bash
node -e "const s=require('fs').readFileSync('app.html','utf8');(s.match(/<script>([\s\S]*?)<\/script>/g)||[]).forEach(b=>new Function(b.replace(/^<script>/,'').replace(/<\/script>$/,'')));console.log('JS OK')"
```

---

## Backend (Supabase)

Projeto `wtbskvimckdsypmuyxen` · região `eu-west-1`.

### Tabelas

Todas com RLS por utilizador — cada pessoa só acede às suas linhas.

| Tabela | Papel |
|---|---|
| `profiles` | Perfil (espelha o onboarding) |
| `plan_progress` | Passos concluídos do plano de chegada |
| `doc_checklist` | Checklists dos processos de documentação |
| `saved_items` | Vagas, casas, eventos e grupos guardados |
| `applications` | Candidaturas e o seu estado |
| `ai_queries` | Perguntas ao assistente (analítica + rate limiting) |

**Regra de segurança:** toda a policy `FOR ALL`/`UPDATE`/`INSERT` tem de ter `WITH CHECK`. Funções `SECURITY DEFINER` têm sempre `search_path` fixo e `EXECUTE` revogado de `anon`/`authenticated`.

### Edge Functions

| Função | JWT | Papel |
|---|---|---|
| `ai-assistant` | sim | Assistente ancorado no conteúdo verificado |

---

## A camada de IA

O assistente é **ancorado (grounded)**: sobre procedimentos oficiais só pode dizer o que está no conteúdo validado da plataforma. Isto torna impossível, por construção, inventar requisitos legais.

Funciona em duas camadas:

1. **No frontend** (`app.html`) — motor de intenções sobre os dados verificados. Funciona sem backend.
2. **Na Edge Function** (`ai-assistant`) — o modelo recebe o conteúdo verificado como única fonte permitida e um system prompt que o obriga a encaminhar quando não sabe.

Ordem de precedência das intenções — **deliberada**:

1. Escalada jurídica (indeferimento, recurso, prazo expirado, situação irregular…)
2. Burlas
3. Só depois trabalho, casa, documentação, etc.

> A segurança tem precedência sobre a intenção aparente. Quem pergunta *"querem enganar-me com um quarto"* precisa do guia anti-burla, não de anúncios.

Quando o caso exige análise profissional, a resposta começa sempre por:

> *"Esta situação pode depender do teu caso. Posso ajudar-te a encontrar um profissional."*

### Configurar o assistente

A chave **nunca** vai no frontend. Define o segredo no Supabase:

```bash
supabase secrets set ANTHROPIC_API_KEY=<a-tua-chave> --project-ref wtbskvimckdsypmuyxen
```

Ou pelo painel: *Edge Functions → ai-assistant → Secrets*.

Sem o segredo, a função responde `503 assistente_nao_configurado` — de propósito, para falhar de forma clara em vez de silenciosa.

---

## Princípios do produto

- **Nunca fingir ser advogado.** A plataforma dá orientação, não aconselhamento jurídico. Onde a diferença importa, está escrito.
- **Proteger quem está mais exposto.** Regras anti-burla no arrendamento, profissionais verificados, denúncia em dois toques.
- **Dizer "não sei".** Preferível a arriscar informação errada sobre a situação legal de alguém.
- **Sem conteúdo fictício em páginas públicas.** Nada de testemunhos inventados nem números de utilizadores falsos.
- **Os dados são da pessoa.** Exportar e apagar conta, sempre disponíveis.

---

## Estado

Feito: landing, app do utilizador (onboarding → plano → documentação → trabalho → casa → profissionais → eventos → comunidade → mapa → pesquisa), 4 painéis multi-role com mensagens internas, consola de admin com moderação e verificações, camada de IA ancorada, schema e Edge Function no Supabase.

A fazer: ligar o frontend ao Supabase (auth + persistência, hoje em `localStorage`), definir `ANTHROPIC_API_KEY`, i18n pt/en/fr, documentos legais antes do lançamento público.
