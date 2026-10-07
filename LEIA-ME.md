# Te Ajudo a Votar

Site simples para pedir e oferecer ajuda para votar no 2º turno, domingo, 25 de outubro de 2026.
Complementa o Instagram [@teajudoavotar](https://www.instagram.com/teajudoavotar/).

Sem cadastro, sem anúncios, sem rastreadores. Funciona bem em celular antigo e internet fraca.

- **No ar:** https://teajudoavotar.com.br (o endereço antigo `guil-is.github.io/teajudoavotar` redireciona para cá)
- **Domínio:** registrado no Registro.br até 07/10/2027, com o DNS do próprio Registro.br apontando para o GitHub Pages.
- **Banco de dados:** projeto `teajudoavotar` no Supabase, organização "Te Ajudo a Votar", região São Paulo.
- **Painel:** https://supabase.com/dashboard/project/ponjknktdmsdgxrsmjjz

Para mudar o site, edite os arquivos aqui no GitHub. O GitHub Pages publica sozinho em 1 ou 2 minutos.

## O que tem nesta pasta

| Arquivo | Para que serve |
|---|---|
| `index.html` | O site inteiro |
| `config.js` | Onde você cola o endereço e a chave do banco de dados |
| `assets/` | Fonte (Figtree, licença OFL em `figtree-OFL.txt`), ícone e imagem de compartilhamento |
| `supabase.sql` | Cria o banco de dados (rodar uma vez no Supabase) |

Sem o banco configurado, o site abre em **modo demonstração**: mostra exemplos e guarda o que a pessoa publica só no próprio aparelho. Serve para testar e mostrar para o time.

## Como foi montado (para refazer do zero)

### 1. Criar o banco de dados no Supabase (grátis)

1. Entre em [supabase.com](https://supabase.com) e crie uma conta.
2. Clique em **New project**. Nome: `teajudoavotar`. Região: **South America (São Paulo)**. Crie uma senha forte e guarde.
3. Espere o projeto ficar pronto (1 a 2 minutos).
4. No menu da esquerda, abra **SQL Editor** e clique em **New query**.
5. Abra o arquivo `supabase.sql`, copie tudo, cole lá e clique em **Run**. Deve aparecer "Success". Avisos em amarelo ("already exists", "does not exist, skipping") são normais.

   **Se o banco já existia:** sempre que o `supabase.sql` mudar aqui no GitHub, rode ele de novo do mesmo jeito. Ele atualiza a tabela e as funções sem apagar o que já foi publicado.

   **Situação em 7/10/2026:** o banco do projeto foi atualizado pelo Claude, direto pela conexão com o Supabase, de um jeito compatível: as colunas antigas `ajudas`, `periodo` e `canais` continuam lá (vazias), a função `criar` antiga continua ao lado da nova, e a limpeza automática da tabela `limites` ficou de fora. O site funciona assim. Para deixar o banco igual ao `supabase.sql`, rode o arquivo no SQL Editor uma vez: ele apaga as colunas e a função antigas e liga a limpeza.
6. Pegue os dois dados de acesso:
   - **Project Settings > Data API**: copie a **Project URL** (algo como `https://abcdefgh.supabase.co`).
   - **Project Settings > API Keys**: copie a **Publishable key** (começa com `sb_publishable_`). Se só aparecer a antiga chave `anon`, pode usar ela.
7. Abra `config.js` e cole os dois entre as aspas:

```js
SUPABASE_URL: 'https://abcdefgh.supabase.co',
SUPABASE_KEY: 'sb_publishable_xxxxxxxx',
```

Essa chave é pública por natureza. Pode ficar no GitHub sem problema: o banco só aceita as ações que o site faz.

### 2. Publicar no GitHub Pages

1. No GitHub, crie um repositório público chamado `teajudoavotar`.
2. Clique em **Add file > Upload files** e arraste `index.html`, `config.js`, a pasta `assets` e este `LEIA-ME.md`. Clique em **Commit changes**.
3. Vá em **Settings > Pages**. Em **Source**, escolha **Deploy from a branch**, branch **main**, pasta **/ (root)**. Salve.
4. Em 1 ou 2 minutos o site estará em `https://SEU-USUARIO.github.io/teajudoavotar/`.

### 3. Ajustar a imagem de compartilhamento

Para o link aparecer com imagem no WhatsApp e no Telegram, abra `index.html` e troque `SEU-USUARIO` pelo seu usuário do GitHub nesta linha:

```html
<meta property="og:image" content="https://SEU-USUARIO.github.io/teajudoavotar/assets/compartilhar.jpg">
```

### 4. Testar

1. Abra o site no celular. A faixa amarela de "Modo demonstração" não deve aparecer.
2. Publique um pedido de teste.
3. No Supabase, abra **Table Editor > posts** e confira se ele está lá.
4. No site, em "Você publicou", toque em **Apagar** duas vezes.

## Como funciona

- Toda página pede para divulgar: um bloco "Ajude a espalhar" com botão de WhatsApp (mensagem pronta com o link), compartilhar ou copiar o link e Instagram. Ele aparece na abertura, no mural (inclusive quando a busca não acha nada), em Mais informações e logo depois de publicar.
- Todas as páginas terminam com um rodapé pequeno com os avisos: iniciativa voluntária e apartidária, sem cadastro, o que é guardado e quando tudo é apagado.
- A página inicial tem só duas ações: **Preciso de ajuda** e **Posso ajudar**. O mural e "Mais informações" ficam em páginas próprias, com links discretos.
- O formulário faz uma pergunta por tela, em 4 passos: primeiro nome, onde mora, contato (WhatsApp ou Instagram, pelo menos um) e um texto opcional.
- No passo "Onde você mora?", a pessoa digita o bairro ou a cidade e escolhe na lista, toca em **Usar onde eu estou** (GPS do celular) ou escreve o endereço à mão. A busca usa o mapa aberto OpenStreetMap, pelo serviço gratuito Photon (`photon.komoot.io`). A localização não é guardada.
- No mural, dá para filtrar por estado, buscar por cidade ou bairro e tocar em **Perto de mim** para ver do mais perto ao mais longe, com a distância em cada cartão. A localização do aparelho fica só na memória do navegador.
- Quando a lista está em uma cidade só (busca ou Perto de mim), aparece uma linha com os bairros que têm anúncios e a contagem. Um toque filtra, outro toque limpa.
- Cada anúncio guarda a posição aproximada do bairro, arredondada para 0,01 grau (cerca de 1 km). Quem usa o buscador ou o GPS tem a posição arredondada no próprio aparelho antes de enviar. Quem escreve o endereço à mão recebe o centro do bairro pelo OpenStreetMap, se ele for encontrado. O banco arredonda de novo ao gravar. O ponto exato nunca é enviado.
- O mural mostra primeiro nome, bairro, cidade, o texto e quais canais de contato existem. O número e o @ só aparecem quando alguém toca em **Entrar em contato**. Daí dá para abrir o WhatsApp, ligar ou mandar mensagem no Instagram.
- Quem publicou vê seus anúncios no topo do mural (no mesmo aparelho) e recebe um link secreto para gerenciar de outro aparelho. Pedido: "Já consegui ajuda" tira o botão de contato e o cartão vai para o fim da lista com o selo "Ajuda encontrada". Oferta: não tem esse botão, porque uma oferta pode ajudar várias pessoas; quem não puder mais ajudar apaga. Os dois tipos podem ser apagados a qualquer momento.
- Depois das 17h de 25/10, o site para de aceitar publicações.

Se um dia o Photon sair do ar, a pessoa ainda consegue publicar escrevendo o endereço à mão. Para trocar o serviço de busca, coloque outro endereço compatível com o Photon em `config.js`, na chave `GEOCODER`.

### Proteções

- Ninguém lê a tabela direto: o site só fala com o banco por funções que validam tudo.
- Cada conexão pode publicar até 6 anúncios por hora e abrir até 60 contatos por hora. Isso atrapalha robôs que querem coletar telefones.
- Denúncias só contam. Nenhum anúncio sai do mural sozinho: um limite automático seria alvo fácil de ataque coordenado contra anúncios legítimos. Quem esconde é a moderação (veja abaixo).
- O banco guarda só um código embaralhado do IP para esses limites, nunca o IP.

## Stories para o Instagram

`story.html` é um editor de story (1080×1920) no estilo da marca: escolha um modelo, edite os textos e baixe o PNG. Funciona no celular e no computador, sem depender de nada externo. Fica em https://teajudoavotar.com.br/story.html, sem link na navegação do site.

## Moderação

Abra **https://teajudoavotar.com.br/admin.html** e entre com a senha de moderação (quem cuida do site tem a senha; ela não fica em lugar nenhum do código). O painel mostra tudo, inclusive anúncios escondidos, com o contato de cada um.

- **Denunciados:** aba que abre primeiro. Leia o anúncio e decida.
- **Esconder:** tira do mural sem apagar. Dá para mostrar de novo.
- **Carona:** aba com os anúncios que mencionam carona, carro, levar, Uber, moto ou transporte (menos "transporte público" e "coletivo"), com um selo no cartão.
- **Editar texto:** abre o texto do anúncio para tirar só o que não pode, como a frase da carona. Avise a pessoa.
- **Completar localizações:** procura no OpenStreetMap o bairro (ou a cidade) dos anúncios publicados antes desta versão e guarda a posição arredondada. Rode uma vez depois de atualizar o banco; os anúncios novos já chegam com a posição.
- **Zerar denúncias:** para anúncios legítimos que foram denunciados de má-fé.
- **Apagar:** definitivo. Pede confirmação com um segundo toque.

Denúncias não escondem nada automaticamente. Combine com o time de olhar a aba "Denunciados" pelo menos duas vezes por dia na última semana e no domingo da votação. Dez senhas erradas seguidas bloqueiam o painel por uma hora.

**Trocar a senha:** no SQL Editor do Supabase, rode (com a sua senha nova no lugar):

```sql
update public.admin_config
   set segredo_hash = encode(sha256(convert_to('SUA-NOVA-SENHA', 'UTF8')), 'hex'), atualizado_em = now()
 where id = 1;
```

O painel também funciona pela tabela: em **Table Editor > posts**, `oculto = true` esconde e `denuncias = 0` limpa as denúncias.

Números da ação:

```sql
select tipo, count(*) as anuncios, count(*) filter (where resolvido) as resolvidos, sum(contatos) as contatos_abertos
from posts group by tipo;
```

## Depois da eleição

O site promete apagar tudo em 26 de outubro. No SQL Editor, rode:

```sql
delete from public.posts;
delete from public.limites;
```

Ou apague o projeto inteiro em **Project Settings > General > Delete project**.

## Se algo der errado

- **Aparece "Não foi possível falar com o mural agora":** confira a URL e a chave em `config.js`. A URL não leva `/rest/v1` no final.
- **Erro de permissão ou função não encontrada:** rode o `supabase.sql` de novo. Confira em **Project Settings > Data API** se a Data API está ligada e se o schema `public` está exposto.
- **O projeto do Supabase "pausou":** projetos grátis pausam depois de 7 dias sem uso. Entre no painel e clique em **Restore**. Abrir o site de vez em quando evita isso.

## Sobre carona

O site não oferece carona de carro de propósito, e barra quem tenta: o formulário mostra a regra no passo do texto, recusa textos com carona, carro, levar, Uber, moto ou transporte (menos "transporte público" e "coletivo") e explica o motivo; o banco faz a mesma checagem. O site não oferece carona de carro de propósito. A Lei 6.091/1974 limita o transporte de eleitores no dia da eleição, e um mural público organizando caronas pode ser lido como transporte irregular. Para o deslocamento, a ajuda fica em ir junto a pé ou de transporte público, que deve ser gratuito no dia da votação.
