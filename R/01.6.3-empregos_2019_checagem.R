# esse script agrega os dados de empregos da etapa do censo escolar por hexagono e depois
# identifica hexagonos problemasticos a partir de dois metodos:
# 1) corrigindo quais hexagonos tem uma concentracao indevida de empregos (geralmente acima de 2000 empregos)
# caso esses hexagnons tenham uma alta proporcao de 3 estrelas, todos os estabelecimentos 3 estrelas dele sao
# levados para o gmaps
# 2) comparando a quantidade de empregos dos hex de um ano para o outro (funcao compare_jobs_distribution.R)
# caso o hexagono tenha um diferenca de 1000 empregos de um ano pra outro, todos os estabelecimentos 3 estrelas
# desses hexagonos sao levados para o gmaps

# toda vez que um rodada de correcao eh feita, todos os anos sao atualizados
# dessa forma, toda rais tera um check (check1) correspondente a chechagem 1) e outros n checks a partir
# da checagem a partir de cada ano em comparacao
# assim, a cada ano que for adicionado e checagem realizado, todos os anos vao sofrer um atualizacao com as novas
# coordenadas rodadas no gmaps


# carregar bibliotecas
source('./R/fun/setup.R')





# 1) agrupar empregos nos hexagonos -----------------------------------------------------------

source("R/fun/agrupar_empregos_hex_teste.R")
agrupar_hex_teste("2019", rais = "../../data/acesso_oport/rais/2019/rais_2019_corrigido_geocoded_censoEscolar.rds")


# 2) Corrigindo hexagonos problematicos --------------------------


# abrir rais
rais <- readr::read_rds("../../data/acesso_oport/rais/2019/rais_2019_corrigido_geocoded_censoEscolar.rds")

# # trazer razao social
# estabs <- fread("../../data-raw/rais/2019/rais_estabs_raw_2019.csv", select = c("id_estab", "razao_social"))
# estabs[, id_estab := str_pad(id_estab, width = 14, pad = 0)]
# estabs <- distinct(estabs, id_estab, .keep_all = TRUE)
# 
# rais <- merge(rais, estabs, by = "id_estab", all.x = TRUE)

# carrega funcoes para correcao
source('./R/fun/diagnost_hex_empregos.R')
source("R/fun/compare_jobs_distribution.R")

# identiicar quais hexagonos tem uma concentracao indevida de empregos (tipo 1)
hex_probs_diag <- lapply(munis_df$abrev_muni, diagnost_hex_empregos, corte = 2000, ano = 2019) %>% do.call(rbind, .)

# identificar heagonos comparando a quantidade de empregos dos hex de um ano para o anterior
hex_probs_compare <- lapply(munis_df$abrev_muni, compare_jobs_distribution, 
                            corte = 1000, ano_bottom = 2018, ano_top = 2019) %>% rbindlist()



# ler hex agregados e juntar
hex <- lapply(sprintf("../../data/acesso_oport/hex_agregados/2019/hex_agregado_%s_09_2019.rds", munis_df$abrev_muni), read_rds) %>%
  rbindlist() %>%
  st_sf() %>%
  select(id_hex) %>%
  # filtra hex ids problematicos
  filter(id_hex %in% c(hex_probs_diag$id_hex, hex_probs_compare$id_hex))


# Qual o codigo dos municipio em questao?
# cod_mun_ok <- munis_df_2019[abrev_muni %in% unique(hex_probs$sigla_muni)]$code_muni

# Carrega somente os dados da rais estabes nestes municipios
base <- rais %>%
  filter(!is.na(lon)) %>%
  # filter(codemun %in% substr(cod_mun_ok, 1, 6)) %>%
  st_as_sf(coords = c("lon", "lat"), crs = 4326) %>%
  select(codemun, id_estab, PrecisionDepth, type_input_galileo, geocode_engine)

# Intersecao do hex ids problema com base de uso do solo
fim <- st_join(base, hex) %>%
  filter(!is.na(id_hex)) %>% setDT()

# # get only new estabs in 2019
# fim_year <- fim[type_input_galileo %like% '2019']

# select only galileo 3 estrelas
fim_filter <- filter(fim, PrecisionDepth == "3 Estrelas")

# Extrair os estabs 'problematicos' concentrados em hexagonos
oi <- fim_filter %>% distinct(id_estab) %>% .$id_estab

# Filtrar estabs
rais_prob <- rais %>%
  filter(id_estab %in% oi)

# lista de enderecos com problema # 10803 estabs
enderecos_etapa7 <- rais_prob %>% 
  mutate(fim = paste0(logradouro, " - ", name_muni, ", ", uf, " - CEP ", cep)) %>% 
  .$fim

# registrar Google API Key
my_api <- data.table::fread("../../data-raw/google_key.txt", header = F)
register_google(key = my_api$V1[3])

# geocode
coordenadas_google_etapa7 <- lapply(X=enderecos_etapa7, ggmap::geocode, output = 'all')

# identify list names as id_estab
names(coordenadas_google_etapa7) <- rais_prob$id_estab 

# save
write_rds(coordenadas_google_etapa7, "../../data/acesso_oport/rais/2019/geocode/rais_2019_output_google_manyhex.rds")
coordenadas_google_etapa7 <- read_rds("../../data/acesso_oport/rais/2019/geocode/rais_2019_output_google_manyhex.rds")

# garantir que sejam os enderecos mesmo
coordenadas_google_etapa7 <- coordenadas_google_etapa7[names(coordenadas_google_etapa7) %in% oi]

create_dt <- function(x) {
  
  precision_depth0 <- ifelse(length(x[["results"]][[1]][["address_components"]]) > 0, 
                             x[["results"]][[1]][["address_components"]], 
                             NA)
  
  # check length from precision depth
  precision_depth <- ifelse(is.na(precision_depth0), NA,
                            ifelse(length(precision_depth0[[1]]$types) > 0,
                                   precision_depth0[[1]]$types[[1]], 
                                   NA))
  
  a <- data.table(
    MatchedAddress = ifelse(!is.null(x[["results"]][[1]][["formatted_address"]]), x[["results"]][[1]][["formatted_address"]], NA),
    # PrecisionDepth = ifelse(!is.null(x[["results"]][[1]][["address_components"]][[1]]$types[[1]]), x[["results"]][[1]][["address_components"]][[1]]$types[[1]], NA),
    PrecisionDepth = precision_depth,
    lon = ifelse(!is.null(x[["results"]][[1]][["geometry"]][["location"]][["lng"]]), x[["results"]][[1]][["geometry"]][["location"]][["lng"]], NA),
    lat = ifelse(!is.null(x[["results"]][[1]][["geometry"]][["location"]][["lat"]]), x[["results"]][[1]][["geometry"]][["location"]][["lat"]], NA)
  )
  
}

# create dt 
enderecos_google_etapa7 <- lapply(coordenadas_google_etapa7, create_dt)


# rbind as data.table
enderecos_google_etapa7_dt <- rbindlist(enderecos_google_etapa7, idcol = "id_estab",
                                        use.names = TRUE)

# identify searchedaddress
searchedaddress <- filter(rais, id_estab %in% names(enderecos_google_etapa7)) %>%
  mutate(SearchedAddress = paste0(logradouro, " - ", name_muni, ", ", uf, " - CEP ", cep)) %>% 
  select(id_estab, SearchedAddress)
enderecos_google_etapa7_dt <- left_join(enderecos_google_etapa7_dt, searchedaddress, by = "id_estab") %>% setDT()
# identify problem
enderecos_google_etapa7_dt[, geocode_engine := 'gmaps_toomany_hex_2019']
# identify quality
enderecos_google_etapa7_dt[is.na(lon), ':='(PrecisionDepth = "address_not_found")]



# bring tot he original dataset de 2019
rais[enderecos_google_etapa7_dt, on = "id_estab",
     c("MatchedAddress", "SearchedAddress", "PrecisionDepth", "lon", "lat", "geocode_engine") := 
       list(i.MatchedAddress, i.SearchedAddress, i.PrecisionDepth, i.lon, i.lat, i.geocode_engine)]


# check
table(rais$PrecisionDepth, useNA = 'always')
table(rais$geocode_engine, useNA = 'always')
table(rais$type_input_galileo, useNA = 'always')


# make stabs are unique
rais <- rais %>% distinct(id_estab, .keep_all = TRUE)


# Salvar
write_rds(rais, "../../data/acesso_oport/rais/2019/check/rais_2019_check1.rds")




# 3) atualizar empregos nos hexagonos para 2019 (check 1) -----------------------------------------------------------
agrupar_hex_teste("2019", rais = "../../data/acesso_oport/rais/2019/check/rais_2019_check1.rds")




# 4) atualizar empregos nos hexagonos para 2018 (check 2) -----------------------------------------------------------
rais_2018 <- read_rds("../../data/acesso_oport/rais/2018/check/rais_2018_check1.rds") %>% setDT()
rais_2019 <- read_rds("../../data/acesso_oport/rais/2019/check/rais_2019_check1.rds")

# get only estabs that  didnt change address
rais_2019 <- rais_2019 %>% filter(type_input_galileo != "cep_changed_2019")
# get only estab that were updated
rais_2019 <- rais_2019 %>% filter(geocode_engine == "gmaps_toomany_hex_2019") %>% setDT()

# update rais 2018
rais_2018[rais_2019, on = "id_estab",
          c("MatchedAddress", "PrecisionDepth", "lon", "lat", "geocode_engine") := 
            list(i.MatchedAddress, i.PrecisionDepth, i.lon, i.lat, i.geocode_engine)
          ]

# save it (check 2)
write_rds(rais_2018, "../../data/acesso_oport/rais/2018/check/rais_2018_check2.rds")

agrupar_hex_teste("2018", rais = "../../data/acesso_oport/rais/2017/check/rais_2018_check2.rds")


# 5) atualizar empregos nos hexagonos para 2017 (check 3) -----------------------------------------------------------
rais_2017 <- read_rds("../../data/acesso_oport/rais/2017/check/rais_2017_check2.rds") %>% setDT()
rais_2019 <- read_rds("../../data/acesso_oport/rais/2019/check/rais_2019_check1.rds")

# get only estabs that didnt change address
rais_2019 <- rais_2019 %>% filter(type_input_galileo %nin% c("cep_changed_2018", "cep_changed_2019"))
# get only estab that were updated
rais_2019 <- rais_2019 %>% filter(geocode_engine == "gmaps_toomany_hex_2019") %>% setDT()

# update rais 2017
rais_2017[rais_2019, on = "id_estab",
          c("MatchedAddress", "PrecisionDepth", "lon", "lat", "geocode_engine") := 
            list(i.MatchedAddress, i.PrecisionDepth, i.lon, i.lat, i.geocode_engine)
          ]

# save rais 2017 (check 3)
write_rds(rais_2017, "../../data/acesso_oport/rais/2017/check/rais_2017_check3.rds")


agrupar_hex_teste("2017", rais = "../../data/acesso_oport/rais/2017/check/rais_2018_check3.rds")




# # 8) Excluir CNPJ's problematicos --------------------------
# 
# # Esse CPNJ foram identificados a partir da inspecao de hexagonos em cada cidade com uma quantidade
# # maior que 3000 empregos
# 
# # Abrir rais da etapa 7
# rais <- read_rds("../../data/acesso_oport/rais/2019/rais_2019_etapa7.rds")
# 
# # Trazer CNPJs problematicos
# # Lista de CNPJS problematicos
# cnpjs_prob <- c("02685728000120","05305430000135", "01437408000198", "04368898000106","04370282000170","19201128000141",
#                 "37162435000142","08689024000101","92966571000101","88630413000796","02539959000125",
#                 "31546484000100","33833880000136","01616929000102","14698658000123","83367342000252",
#                 "04113174000111","02295753000105","50844182001208","08848807000190","06019070000178",
#                 "09347229000171","12294708000181","02773312000163","07442731000136","01602361000170")
# 
# # Excluir esses CNPJs da rais
# rais_etapa8 <- rais[id_estab %nin% cnpjs_prob]
# 
# # Salvar RAIS etapa 8 
# write_rds(rais_etapa8, "../../data/acesso_oport/rais/2019/rais_2019_etapa8.rds")
# 
# 
# 
# 
# 
# 
# 
# # 9) Corrigir a posteriori hex que apresentaram grande diferença pro ano anterior --------------------------
# # Nesse caso, aqui sao os hex que apresentaram um valor muito maior (>1000 vinculos) pra 2018 do que para 2019
# 
# # abrir rais
# rais <- readr::read_rds("../../data/acesso_oport/rais/2019/rais_2019_etapa8.rds")
# 
# # sigla_munii <- 'for'
# 
# # function by city
# compare_jobs_distribution <- function(sigla_munii) {
#   
#   # open hex files
#   hex_jobs_2018 <- read_rds(sprintf("../../data/acesso_oport/hex_agregados/2018/hex_agregado_%s_09_2018.rds",
#                                     sigla_munii)) %>%
#     mutate(ano_jobs = 2018)
#   
#   hex_jobs_2019 <- read_rds(sprintf("../../data/acesso_oport/hex_agregados/2019/hex_agregado_%s_09_2019.rds",
#                                     sigla_munii)) %>%
#     mutate(ano_jobs = 2019)
#   
#   hex_jobs <- rbind(hex_jobs_2018, hex_jobs_2019)
#   hex_jobs <- select(hex_jobs, id_hex, sigla_muni, empregos_total, ano_jobs, geometry) %>% setDT()
#   
#   hex_jobs_wide <- pivot_wider(hex_jobs, names_from = ano_jobs, values_from = empregos_total,
#                                names_prefix = "jobs_")
#   
#   # compare!
#   hex_jobs_wide <- hex_jobs_wide %>%
#     mutate(dif1_abs = jobs_2019 - jobs_2018) %>%
#     mutate(dif1_log = log(jobs_2019/jobs_2018)) %>%
#     # truncate
#     mutate(dif1_abs_tc = case_when(dif1_abs < -500 ~ -500,
#                                    dif1_abs > 500 ~ 500,
#                                    TRUE ~ dif1_abs)) %>%
#     mutate(dif1_log_tc = case_when(dif1_log < -1 ~ -1,
#                                    dif1_log > 1 ~ 1,
#                                    TRUE ~ dif1_log))
#   
#   
#   hex_jobs_wide <- hex_jobs_wide %>%
#     filter(!(jobs_2018 == 0 & jobs_2019 == 0))
#   
#   # filter hex with a diffrence of more than 1000 vinc
#   hex_probs <- filter(hex_jobs_wide, dif1_abs > 1000) %>%
#     select(sigla_muni, id_hex, dif1_abs)
#   
# }
# 
# hex_probs9 <- lapply(munis_df$abrev_muni, compare_jobs_distribution)
# hex_probs9_dt <- do.call(rbind, hex_probs9) 
# 
# 
# # ler hex agregados e juntar
# hex <- lapply(sprintf("../../data/acesso_oport/hex_agregados/2019/hex_agregado_%s_09_2019.rds", unique(hex_probs9_dt$sigla_muni)), read_rds) %>%
#   rbindlist() %>%
#   st_sf() %>%
#   select(id_hex) %>%
#   # filtra hex ids problematicos
#   filter(id_hex %in% hex_probs9_dt$id_hex)
# 
# # Qual o codigo dos municipio em questao?
# cod_mun_ok <- munis_df[abrev_muni %in% unique(hex_probs9_dt$sigla_muni)]$code_muni
# 
# # Carrega somente os dados da rais estabes nestes municipios
# base <- rais %>%
#   filter(!is.na(lon)) %>%
#   filter(codemun %in% substr(cod_mun_ok, 1, 6)) %>%
#   filter(PrecisionDepth %in% c("4 Estrelas", "3 Estrelas", "street_number", "route")) %>%
#   st_as_sf(coords = c("lon", "lat"), crs = 4326) %>%
#   select(codemun, id_estab)
# 
# # Intersecao do hex ids problema com base de uso do solo
# fim <- st_join(base, hex) %>%
#   filter(!is.na(id_hex))
# 
# # Extrair os estabs 'problematicos' concentrados em hexagonos
# oi <- fim %>% st_set_geometry(NULL) %>% distinct(id_estab) %>% .$id_estab
# 
# # Filtrar estabs
# rais_prob <- rais %>%
#   filter(id_estab %in% oi)
# 
# # lista de enderecos com problema
# enderecos_etapa9 <- rais_prob %>% 
#   mutate(fim = paste0(logradouro, " - ", name_muni, ", ", uf, " - CEP ", cep)) %>% 
#   .$fim
# 
# 
# # registrar Google API Key
# my_api <- data.table::fread("../../data-raw/google_key.txt", header = F)
# register_google(key = my_api$V1[2])
# 
# # geocode
# coordenadas_google_etapa9 <- lapply(X=enderecos_etapa9, ggmap::geocode, output = 'all')
# 
# # identify list names as id_estab
# names(coordenadas_google_etapa9) <- rais_prob$id_estab 
# 
# # save
# write_rds(coordenadas_google_etapa9, "../../data/acesso_oport/rais/2019/geocode/rais_2019_output_google_etapa9.rds")
# coordenadas_google_etapa9 <- read_rds("../../data/acesso_oport/rais/2019/geocode/rais_2019_output_google_etapa9.rds")
# 
# create_dt <- function(x) {
#   
#   precision_depth0 <- ifelse(length(x[["results"]][[1]][["address_components"]]) > 0, 
#                              x[["results"]][[1]][["address_components"]], 
#                              NA)
#   
#   # check length from precision depth
#   precision_depth <- ifelse(is.na(precision_depth0), NA,
#                             ifelse(length(precision_depth0[[1]]$types) > 0,
#                                    precision_depth0[[1]]$types[[1]], 
#                                    NA))
#   
#   a <- data.table(
#     MatchedAddress = ifelse(!is.null(x[["results"]][[1]][["formatted_address"]]), x[["results"]][[1]][["formatted_address"]], NA),
#     # PrecisionDepth = ifelse(!is.null(x[["results"]][[1]][["address_components"]][[1]]$types[[1]]), x[["results"]][[1]][["address_components"]][[1]]$types[[1]], NA),
#     PrecisionDepth = precision_depth,
#     lon = ifelse(!is.null(x[["results"]][[1]][["geometry"]][["location"]][["lng"]]), x[["results"]][[1]][["geometry"]][["location"]][["lng"]], NA),
#     lat = ifelse(!is.null(x[["results"]][[1]][["geometry"]][["location"]][["lat"]]), x[["results"]][[1]][["geometry"]][["location"]][["lat"]], NA)
#   )
#   
# }
# 
# # create dt 
# enderecos_google_etapa9 <- lapply(coordenadas_google_etapa9, create_dt)
# 
# 
# # rbind as data.table
# enderecos_google_etapa9_dt <- rbindlist(enderecos_google_etapa9, idcol = "id_estab",
#                                         use.names = TRUE)
# 
# # identify searchedaddress
# enderecos_google_etapa9_dt[, SearchedAddress := enderecos_etapa9]
# # identify problem
# enderecos_google_etapa9_dt[, geocode_engine := 'gmaps_etapa9']
# # identify quality
# enderecos_google_etapa9_dt[is.na(lon), ':='(PrecisionDepth = "address_not_found")]
# 
# 
# 
# # bring tot he original dataset
# rais[enderecos_google_etapa9_dt, on = "id_estab",
#      c("MatchedAddress", "SearchedAddress", "PrecisionDepth", "lon", "lat", "geocode_engine") := 
#        list(i.MatchedAddress, i.SearchedAddress, i.PrecisionDepth, i.lon, i.lat, i.geocode_engine)]
# 
# 
# table(rais$PrecisionDepth, useNA = 'always')
# table(rais$geocode_engine, useNA = 'always')
# table(rais$type_input_galileo, useNA = 'always')
# 
# 
# # Salvar
# write_rds(rais, "../../data/acesso_oport/rais/2019/rais_2019_etapa9.rds")
# 
# 
# 
# 
# 
# 
# 
# 
# # 10) Analisar CNPJ de hex problematicos das comparacaoes com o ano anterior -----------------------
# 
# 
# # abrir rais
# rais <- readr::read_rds("../../data/acesso_oport/rais/2019/rais_2019_etapa9.rds")
# 
# # remove lat lon missing
# rais <- rais[!is.na(lat), ]
# 
# # filter only estabs with high wuality geocode
# rais <- rais[PrecisionDepth %in% c("4 Estrelas", "3 Estrelas", "street_number", "route")]
# 
# # trazer razao social
# estabs <- fread("../../data-raw/rais/2019/rais_estabs_raw_2019.csv", select = c("id_estab", "razao_social"))
# estabs[, id_estab := str_pad(id_estab, width = 14, pad = 0)]
# 
# estabs <- estabs %>% distinct(id_estab, .keep_all = TRUE)
# 
# rais <- merge(rais, estabs, by = "id_estab", all.x = TRUE)
# 
# # sigla_munii <- 'spo'
# 
# # function by city
# compare_jobs_distribution <- function(sigla_munii) {
#   
#   # open hex files
#   hex_jobs_2018 <- read_rds(sprintf("../../data/acesso_oport/hex_agregados/2018/hex_agregado_%s_09_2018.rds",
#                                     sigla_munii)) %>%
#     mutate(ano_jobs = 2018)
#   
#   hex_jobs_2019 <- read_rds(sprintf("../../data/acesso_oport/hex_agregados/2019/hex_agregado_%s_09_2019.rds",
#                                     sigla_munii)) %>%
#     mutate(ano_jobs = 2019)
#   
#   hex_jobs <- rbind(hex_jobs_2018, hex_jobs_2019)
#   hex_jobs <- select(hex_jobs, id_hex, sigla_muni, empregos_total, ano_jobs, geometry) %>% setDT()
#   
#   hex_jobs_wide <- pivot_wider(hex_jobs, names_from = ano_jobs, values_from = empregos_total,
#                                names_prefix = "jobs_")
#   
#   # compare!
#   hex_jobs_wide <- hex_jobs_wide %>%
#     mutate(dif1_abs = jobs_2019 - jobs_2018) %>%
#     mutate(dif1_log = log(jobs_2019/jobs_2018)) %>%
#     # truncate
#     mutate(dif1_abs_tc = case_when(dif1_abs < -500 ~ -500,
#                                    dif1_abs > 500 ~ 500,
#                                    TRUE ~ dif1_abs)) %>%
#     mutate(dif1_log_tc = case_when(dif1_log < -1 ~ -1,
#                                    dif1_log > 1 ~ 1,
#                                    TRUE ~ dif1_log))
#   
#   
#   hex_jobs_wide <- hex_jobs_wide %>%
#     filter(!(jobs_2018 == 0 & jobs_2019 == 0))
#   
#   # filter hex with a diffrence of more than 1000 vinc
#   hex_probs <- filter(hex_jobs_wide, dif1_abs > 1000) %>%
#     select(sigla_muni, id_hex, dif1_abs)
#   
# }
# 
# hex_probs9 <- lapply(munis_df$abrev_muni, compare_jobs_distribution)
# hex_probs9_dt <- do.call(rbind, hex_probs9) 
# 
# 
# # ler hex agregados e juntar
# hex <- lapply(sprintf("../../data/acesso_oport/hex_agregados/2019/hex_agregado_%s_09_2019.rds", unique(hex_probs9_dt$sigla_muni)), read_rds) %>%
#   rbindlist() %>%
#   st_sf() %>%
#   select(id_hex) %>%
#   # filtra hex ids problematicos
#   filter(id_hex %in% hex_probs9_dt$id_hex)
# 
# # Qual o codigo dos municipio em questao?
# cod_mun_ok <- munis_df[abrev_muni %in% unique(hex_probs9_dt$sigla_muni)]$code_muni
# 
# # Carrega somente os dados da rais estabes nestes municipios
# base <- rais %>%
#   filter(!is.na(lon)) %>%
#   filter(codemun %in% substr(cod_mun_ok, 1, 6)) %>%
#   filter(PrecisionDepth %in% c("4 Estrelas", "3 Estrelas", "street_number", "route")) %>%
#   st_as_sf(coords = c("lon", "lat"), crs = 4326) 
# # select(codemun, id_estab)
# 
# # Intersecao do hex ids problema com base de uso do solo
# fim <- st_join(base, hex) %>%
#   filter(!is.na(id_hex))
# 
# # maybe these rrepreents a cnpj problem
# fim1 <- fim %>%
#   st_set_geometry(NULL) %>%
#   group_by(name_muni, id_hex) %>%
#   mutate(sum = sum(total_corrigido)) %>%
#   mutate(prop = total_corrigido/sum) %>%
#   ungroup() %>%
#   filter(prop > 0.5) %>%
#   select(id_estab, razao_social, total_corrigido, prop)
# 
# 
# # tirar esses cnpjs
# rais_fim <- rais[id_estab %nin% fim1$id_estab]
# 
# # salvar
# write_rds(rais_fim, "../../data/acesso_oport/rais/2019/rais_2019_etapa10.rds")
