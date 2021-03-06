OTP - Setup
================
Ipea
19 de março de 2019

# OTP Setup

## Download do arquivo .pbf

O arquivo pbf de cada cidade pode ser baixado a partir do site [HOT
Export Tool](https://export.hotosm.org/en/v3/exports/new/describe). Lá,
escreva o nome da cidade na barra de pesquisa do lado direito e
selecione o município (checar o país). Automaticamente o mapa vai dar um
zoom no município, com o bounding box delimitado. Feito isso, no lado
direito, coloque o nome do seu export (sugestão: três primeiras letras
da cidade) e aperte `NEXT`. Na aba `2 Formats` que vai aparecer,
selecione o formato OSM `.pbf` e aperte `NEXT`. Na aba `3 Data` que
aparece, selecione somente o tipo `Transportation`, que é o necessário
para o projeto, e aperte `NEXT`. Por fim, na aba `4 Summary`, clique em
`Create Export` e espere o arquivo estar disponível para download.
Descompactar o arquivo na pasta do município na paste `../otp/graphs`.

Há outra forma de fazer o download do arquivo `.pbf`através do pacote
`osmdata`. Uma função foi criada na tentativa de aplicar essa
metodologia reproduzível, porém o resultado das funções estão sujeitos a
inconsistências.

``` r
cidade <- "porto alegre"

download_pbf <- function(cidade) {
  
  cidade_string <- paste0(cidade, ", brazil")
  
  # Tags disponiveis
  vai <- available_tags("highway")
  
  features <- opq (cidade_string) %>%
    add_osm_feature(key = "highway", value = vai)
  
  # Exportar arquivo .pbf para o disco
  cidade_short <- substr(cidade, 1, 3)
  path_out <- sprintf("../otp/graphs/%s/%s.pbf", cidade_short, cidade_short)
  osmdata_pbf(features, path_out)

}
```

## Criação dos graphs

A função `construir_graph` constrói o arquivo `Graph.obj`, que é
necessário para as operações do OTP. O único argumento necessário para
a construção do graph é o nome da cidade, que já deve estar com uma
pasta criada com os arquivo `.pbf`e `GTFS` referentes.

``` r
source("R/3-otp.R")

construir_graph("for")
construir_graph("bel")
construir_graph("rio")
construir_graph("sao")
construir_graph("cur")
construir_graph("por")
```

Atestar qualidade do GTFS através do `feedvalidator`:

``` r
source("R/3-feed_validator.R")
```

Próxima etapa: baixar os arquivos .pbf a partir do pacote `osmdata`.

``` r
getbb ("belo horizonte")

vai <- available_tags("highway")

q <- opq ("belo horizonte") %>%
  add_osm_feature(key = "highway", value = vai)
  # osmdata_sf()
  
osmdata_pbf(q, "bel_teste.osm.pbf")


meu <- q[["osm_lines"]] %>%
  st_sf()

# Before that
# sudo apt-get install sqlite3 libsqlite3-dev

meu %>%
  st_write("teste_bel.pbf")

ooo <- st_read("../otp/graphs/for/fortaleza_export.pbf")
```
