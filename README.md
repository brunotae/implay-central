# Implay Central

Sistema da Implay: lives e agenda, vagas para freelancers, marcas e jobs, propostas, equipe, estúdios, financeiro e relatórios.

- Roda no **mesmo Supabase do Implay Despesas** (mesmo login para os sócios).
- Hospedado no GitHub Pages: `https://brunotae.github.io/Implay-central/`

## Níveis de acesso

| | ADM | Gerência | Consulta | Seller |
|---|---|---|---|---|
| Painel, agenda, jobs, propostas, estúdios, relatórios | vê e edita | vê e edita | só vê | — |
| Equipe freelancer | vê e edita | vê e edita | só vê | só o próprio cadastro |
| Financeiro (receber, pagar freelancers, reembolsos) | ✓ | — | — | só os próprios pagamentos |
| Acessos | ✓ | — | — | — |
| Vagas abertas / candidatura | — | — | — | ✓ (só da própria função) |

As regras estão no banco (`supabase/central-1.sql`), então não dá para burlar pelo app.

## Como funciona o fluxo

1. **Marca → Job**: cada job é uma campanha ou contrato, que passa por 9 etapas: Lead, Proposta, Contrato, Briefing, Escala, No ar, Relatório, Faturado e Pago.
2. **Live**: toda live pertence a um job. Você pode escolher o host e o operador direto ou abrir a vaga.
3. **Vaga aberta**: aparece no celular dos freelancers daquela função. A pessoa se candidata e a gerência confirma. A confirmação preenche a vaga e recusa as outras candidaturas.
4. **Pôr no ar → Encerrar**: ao encerrar, você lança GMV, pedidos e pico. O banco cria sozinho o pagamento do host e do operador (horas × valor por hora).
5. **Financeiro**: a receber das marcas, pagamentos dos freelancers (com NF) e reembolsos dos sócios, que vêm do Implay Despesas.

Tudo fica registrado no **Histórico**, inclusive cada candidatura, confirmação e desistência. Isso é a prova de que o freelancer escolhe os próprios jobs.

## Para o ERP (Gabriel)

Tabelas: `marcas`, `jobs`, `propostas`, `freelancers`, `lives`, `candidaturas`, `pagamentos_freela`, `recebimentos`, `recados` e `central_log`, além das do Despesas (`profiles`, `convites`, `despesas`, `reembolsos`, `historico`). É Postgres puro.
