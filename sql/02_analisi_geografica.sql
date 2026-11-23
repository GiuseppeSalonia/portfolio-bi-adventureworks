/* =====================================================================
   PORTFOLIO BI - ADVENTUREWORKS
   File 02 - Analisi geografica delle vendite online
   ---------------------------------------------------------------------
   Database : AdventureWorksDW2025 su SQL Server 2025
   Canale   : Internet (FactInternetSales)
   Scopo    : capire dove si vende, con quali margini, e se la stagionalità
              vista nel file 01 cambia tra emisfero nord ed emisfero sud.

   Contenuto
     1. Struttura dei territori e controlli
     2. Vendite e margini per paese
     3. Stagionalità per emisfero
     4. Sintesi delle scoperte

   Definizioni: le stesse del file 01 (Fatturato = SalesAmount,
   Margine lordo = SalesAmount - TotalProductCost, anni completi 2011-2013).

   I numeri citati nei commenti sono i risultati delle query di questo file.
   ===================================================================== */

USE AdventureWorksDW2025;
GO


-- =====================================================================
-- 1. STRUTTURA DEI TERRITORI E CONTROLLI
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1.1 Quali territori esistono, come sono raggruppati e quali hanno vendite online?
--     Parto dalla dimensione con LEFT JOIN: un territorio senza vendite resta visibile.
-- ---------------------------------------------------------------------

-- Passo 1: totali delle vendite per territorio (anni completi)
WITH VenditePerTerritorio AS (
    SELECT
        f.SalesTerritoryKey,
        COUNT(DISTINCT f.SalesOrderNumber)      AS NumeroOrdini,
        COUNT(DISTINCT f.CustomerKey)           AS NumeroClienti,
        SUM(f.SalesAmount)                      AS Fatturato
    FROM dbo.FactInternetSales  AS f
    JOIN dbo.DimDate            AS d   ON f.OrderDateKey = d.DateKey
    WHERE d.CalendarYear BETWEEN 2011 AND 2013
    GROUP BY f.SalesTerritoryKey
)

-- Passo 2: tutti i territori della dimensione, con le vendite dove ci sono
SELECT
    t.SalesTerritoryKey                                     AS ChiaveTerritorio,
    t.SalesTerritoryGroup                                   AS Gruppo,      -- livello 1: macro-area
    t.SalesTerritoryCountry                                 AS Paese,       -- livello 2
    t.SalesTerritoryRegion                                  AS Regione,     -- livello 3
    COALESCE(v.NumeroOrdini, 0)                             AS NumeroOrdini,
    COALESCE(v.NumeroClienti, 0)                            AS NumeroClienti,
    CAST(COALESCE(v.Fatturato, 0) AS DECIMAL(12,2))         AS Fatturato,
    CAST(100.0 * COALESCE(v.Fatturato, 0)
         / SUM(v.Fatturato) OVER ()
         AS DECIMAL(5,2))                                   AS QuotaFatturatoPerc
FROM dbo.DimSalesTerritory      AS t
LEFT JOIN VenditePerTerritorio  AS v   ON t.SalesTerritoryKey = v.SalesTerritoryKey
ORDER BY Gruppo, Paese, Regione;

/*
FATTI
- La dimensione ha 11 righe: 10 territori reali e una riga segnaposto "NA" senza vendite,
  che con un JOIN normale non si sarebbe vista.
- Le macro-aree sono tre: North America 38,68% del fatturato (11,32 milioni), Pacific 30,86%
  (9,03 milioni, la sola Australia) ed Europe 30,46% (8,92 milioni).
- Solo gli Stati Uniti sono divisi in regioni, cinque. Le vendite online sono quasi tutte a
  ovest: Southwest 19,47% e Northwest 12,43% del totale, cioè il 99,77% degli Stati Uniti.
  Central, Northeast e Southeast fanno insieme 34 ordini e 21.697,17 di fatturato.
- Controlli: il totale è 29.269.561,45 (2 centesimi di arrotondamento rispetto al file 01)
  e le cinque regioni degli Stati Uniti sommano 9.357.412,76, come nella query 2.1.

IPOTESI
- Tre regioni degli Stati Uniti quasi vuote sono con ogni probabilità una caratteristica del
  dataset: i clienti online sembrano concentrati sulla costa ovest. Si può verificare con lo
  stato del cliente in DimGeography.

DECISIONE
- Nel modello tengo i tre livelli (gruppo, paese, regione) ma analizzo per paese: la regione
  aggiunge dettaglio solo per gli Stati Uniti. La riga "NA" non serve per le vendite online.
*/


-- ---------------------------------------------------------------------
-- 1.2 Controllo di qualità: il territorio scritto sulla vendita è lo stesso
--     del cliente? (cliente -> DimCustomer -> DimGeography -> territorio)
-- ---------------------------------------------------------------------
SELECT
    COUNT(*)                                                AS RigheVendita,
    SUM(CASE WHEN f.SalesTerritoryKey =  g.SalesTerritoryKey
             THEN 1 ELSE 0 END)                             AS RigheStessoTerritorio,
    SUM(CASE WHEN f.SalesTerritoryKey <> g.SalesTerritoryKey
             THEN 1 ELSE 0 END)                             AS RigheTerritorioDiverso,
    COUNT(*) - COUNT(g.GeographyKey)                        AS RigheSenzaGeografia
FROM dbo.FactInternetSales      AS f
LEFT JOIN dbo.DimCustomer       AS c   ON f.CustomerKey  = c.CustomerKey
LEFT JOIN dbo.DimGeography      AS g   ON c.GeographyKey = g.GeographyKey;

/*
FATTI
- Tutte le 60.398 righe hanno lo stesso territorio sulla vendita e sull'anagrafica del
  cliente: nessuna riga diversa, nessun cliente senza geografia.
- Ogni cliente appartiene quindi a un solo territorio: in questo file il numero di clienti
  si può sommare tra paesi, e città e stato del cliente (DimGeography) si possono usare
  per un dettaglio più fine.
*/


-- ---------------------------------------------------------------------
-- 1.3 In quale valuta compra ogni paese?
-- ---------------------------------------------------------------------
SELECT
    t.SalesTerritoryCountry                         AS Paese,
    cu.CurrencyAlternateKey                         AS CodiceValuta,
    cu.CurrencyName                                 AS Valuta,
    COUNT(*)                                        AS RigheVendita,
    CAST(SUM(f.SalesAmount) AS DECIMAL(12,2))       AS Fatturato
FROM dbo.FactInternetSales      AS f
JOIN dbo.DimSalesTerritory      AS t   ON f.SalesTerritoryKey = t.SalesTerritoryKey
JOIN dbo.DimCurrency            AS cu  ON f.CurrencyKey       = cu.CurrencyKey
GROUP BY t.SalesTerritoryCountry, cu.CurrencyAlternateKey, cu.CurrencyName
ORDER BY Paese, Fatturato DESC;

/*
FATTI
- Il paese non determina la valuta. Francia e Germania comprano quasi sempre in dollari USA
  (98,2% e 98,6% delle righe); franco francese e marco tedesco compaiono in poche righe
  (59 e 76) e l'euro non compare mai.
- Anche Australia, Canada e Regno Unito hanno una parte di righe in dollari USA (357, 511
  e 205), e gli Stati Uniti hanno 26 righe in dollari canadesi.
- Controllo: le righe delle 13 combinazioni sommano 60.398.

IPOTESI
- Le righe in franchi e in marchi valgono in media circa 3.060 e 3.129 l'una, come le bici
  premium del 2011: potrebbero appartenere solo al primo periodo di vendita.

DECISIONE
- CurrencyKey non è un'informazione geografica affidabile: per la geografia uso il territorio.
*/


-- ---------------------------------------------------------------------
-- 1.4 Gli importi sono convertiti nella valuta del cliente?
--     Se lo fossero, lo stesso prodotto avrebbe prezzi diversi da una valuta all'altra.
-- ---------------------------------------------------------------------

-- Passo 1: per ogni prodotto, in quante valute è venduto e con quanti prezzi diversi
WITH PerProdotto AS (
    SELECT
        f.ProductKey,
        COUNT(DISTINCT f.CurrencyKey)       AS NumeroValute,
        COUNT(DISTINCT f.UnitPrice)         AS NumeroPrezzi
    FROM dbo.FactInternetSales AS f
    GROUP BY f.ProductKey
)

-- Passo 2: quanti prodotti venduti in più valute hanno più di un prezzo
SELECT
    COUNT(*)                                                    AS Prodotti,
    SUM(CASE WHEN NumeroValute > 1
             THEN 1 ELSE 0 END)                                 AS ProdottiInPiuValute,
    SUM(CASE WHEN NumeroValute > 1 AND NumeroPrezzi > 1
             THEN 1 ELSE 0 END)                                 AS DiCuiConPiuPrezzi
FROM PerProdotto;

/*
FATTI
- Tutti i 158 prodotti sono venduti in più valute e nessuno ha più di un prezzo: lo stesso
  prodotto ha lo stesso prezzo in dollari USA, dollari australiani, sterline e così via.
  Gli importi non sono convertiti nella valuta del cliente.
- Ogni ProductKey ha un solo prezzo in tutto il periodo.

IPOTESI
- Gli importi sono tutti espressi in dollari USA (è il prezzo pagato dai clienti degli Stati
  Uniti) e CurrencyKey indica solo la valuta del pagamento.
- Nel file 01 i prezzi di alcuni modelli salgono del 12%: se ogni chiave ha un solo prezzo,
  un aumento sembra creare un nuovo ProductKey. Nelle viste converrà raggruppare per
  modello o per nome del prodotto, non per chiave.

DECISIONE
- Sommo SalesAmount tra paesi senza conversioni e non porto la valuta nel modello.
*/


-- =====================================================================
-- 2. VENDITE E MARGINI PER PAESE
-- =====================================================================

-- ---------------------------------------------------------------------
-- 2.1 Quanto vende ogni paese, come cresce e con quale margine? (2011-2013)
--     Gli anni diventano colonne con SUM(CASE WHEN ...): una riga per paese.
-- ---------------------------------------------------------------------

-- Passo 1: totali per paese
WITH PerPaese AS (
    SELECT
        t.SalesTerritoryCountry                                         AS Paese,
        COUNT(DISTINCT f.CustomerKey)                                   AS NumeroClienti,
        COUNT(DISTINCT f.SalesOrderNumber)                              AS NumeroOrdini,
        SUM(CASE WHEN d.CalendarYear = 2011 THEN f.SalesAmount ELSE 0 END)  AS Fatturato2011,
        SUM(CASE WHEN d.CalendarYear = 2012 THEN f.SalesAmount ELSE 0 END)  AS Fatturato2012,
        SUM(CASE WHEN d.CalendarYear = 2013 THEN f.SalesAmount ELSE 0 END)  AS Fatturato2013,
        SUM(f.SalesAmount)                                              AS Fatturato,
        SUM(f.SalesAmount - f.TotalProductCost)                         AS Margine
    FROM dbo.FactInternetSales      AS f
    JOIN dbo.DimDate                AS d   ON f.OrderDateKey      = d.DateKey
    JOIN dbo.DimSalesTerritory      AS t   ON f.SalesTerritoryKey = t.SalesTerritoryKey
    WHERE d.CalendarYear BETWEEN 2011 AND 2013
    GROUP BY t.SalesTerritoryCountry
)

-- Passo 2: quote e indicatori
SELECT
    Paese,
    NumeroClienti,
    NumeroOrdini,
    CAST(Fatturato2011 AS DECIMAL(12,2))                    AS Fatturato2011,
    CAST(Fatturato2012 AS DECIMAL(12,2))                    AS Fatturato2012,
    CAST(Fatturato2013 AS DECIMAL(12,2))                    AS Fatturato2013,
    CAST(Fatturato     AS DECIMAL(12,2))                    AS FatturatoTotale,
    CAST(100.0 * Fatturato / SUM(Fatturato) OVER ()
         AS DECIMAL(5,2))                                   AS QuotaFatturatoPerc,
    CAST(100.0 * Margine / Fatturato AS DECIMAL(5,2))       AS MarginePerc,
    CAST(Fatturato / NumeroClienti AS DECIMAL(10,2))        AS FatturatoPerCliente
FROM PerPaese
ORDER BY FatturatoTotale DESC;

/*
FATTI
- Controlli: il fatturato dei sei paesi somma 29.269.561,45 (2 centesimi di arrotondamento
  rispetto al file 01) e gli ordini 26.774 (2.216 + 3.269 + 21.289). I clienti attivi nel
  2011-2013 sono 17.977.
- Stati Uniti (31,97%) e Australia (30,86%) fanno insieme il 62,8% del fatturato. Seguono
  Regno Unito 11,57%, Germania 9,88%, Francia 9,01% e Canada 6,71%.
- L'Australia ha meno della metà dei clienti degli Stati Uniti (3.543 contro 7.549) ma quasi
  lo stesso fatturato: 2.549,13 per cliente contro 1.239,56. Nel 2011 era il primo mercato
  (2,56 milioni contro 2,46).
- Il calo del 2012 non è uguale ovunque. Scendono Canada (-46,2%), Stati Uniti (-41,5%) e
  Australia (-17,0%); crescono Francia (+57,7%), Regno Unito (+29,4%) e Germania (+16,9%).
  Nel complesso: Nord America -42,4%, Europa +32,9%.
- Nel 2013 crescono tutti: da 2,0 volte (Australia) a 3,8 volte (Stati Uniti).
- Il margine % è quasi uguale ovunque: da 40,66% (Australia) a 41,89% (Canada).
- Ordini per cliente: Canada 2,07, Australia 1,85, Stati Uniti 1,22.

IPOTESI
- Il calo del 2012 è l'effetto mix del file 01 (uscita dei modelli premium): se ha colpito
  soprattutto il Nord America, lì nel 2011 quei modelli dovevano pesare di più.
  Verificata nella query 2.3: non è così.
*/


-- ---------------------------------------------------------------------
-- 2.2 Perché il margine % cambia da un paese all'altro? Confronto del mix di prodotti (2013)
-- ---------------------------------------------------------------------

-- Passo 1: totali per paese, con il fatturato diviso per categoria e per linea di bici
WITH PerPaese AS (
    SELECT
        t.SalesTerritoryCountry                                         AS Paese,
        SUM(f.SalesAmount)                                              AS Fatturato,
        SUM(f.SalesAmount - f.TotalProductCost)                         AS Margine,
        SUM(CASE WHEN pc.EnglishProductCategoryName = 'Bikes'
                 THEN f.SalesAmount ELSE 0 END)                         AS FatturatoBici,
        SUM(CASE WHEN pc.EnglishProductCategoryName = 'Bikes'
                 THEN f.OrderQuantity ELSE 0 END)                       AS PezziBici,
        SUM(CASE WHEN ps.EnglishProductSubcategoryName = 'Mountain Bikes'
                 THEN f.SalesAmount ELSE 0 END)                         AS FatturatoMountain,
        SUM(CASE WHEN ps.EnglishProductSubcategoryName = 'Road Bikes'
                 THEN f.SalesAmount ELSE 0 END)                         AS FatturatoRoad,
        SUM(CASE WHEN ps.EnglishProductSubcategoryName = 'Touring Bikes'
                 THEN f.SalesAmount ELSE 0 END)                         AS FatturatoTouring
    FROM dbo.FactInternetSales      AS f
    JOIN dbo.DimDate                AS d   ON f.OrderDateKey          = d.DateKey
    JOIN dbo.DimSalesTerritory      AS t   ON f.SalesTerritoryKey     = t.SalesTerritoryKey
    JOIN dbo.DimProduct             AS p   ON f.ProductKey            = p.ProductKey
    JOIN dbo.DimProductSubcategory  AS ps  ON p.ProductSubcategoryKey = ps.ProductSubcategoryKey
    JOIN dbo.DimProductCategory     AS pc  ON ps.ProductCategoryKey   = pc.ProductCategoryKey
    WHERE d.CalendarYear = 2013
    GROUP BY t.SalesTerritoryCountry
)

-- Passo 2: margine, peso delle bici, prezzo medio e peso di ogni linea sul fatturato bici
SELECT
    Paese,
    CAST(Fatturato AS DECIMAL(12,2))                                    AS Fatturato,
    CAST(100.0 * Margine / Fatturato AS DECIMAL(5,2))                   AS MarginePerc,
    CAST(100.0 * FatturatoBici / Fatturato AS DECIMAL(5,2))             AS QuotaBiciPerc,
    CAST(FatturatoBici / NULLIF(PezziBici, 0) AS DECIMAL(10,2))         AS PrezzoMedioBici,
    CAST(100.0 * FatturatoMountain / NULLIF(FatturatoBici, 0)
         AS DECIMAL(5,2))                                               AS QuotaMountainPerc,
    CAST(100.0 * FatturatoRoad / NULLIF(FatturatoBici, 0)
         AS DECIMAL(5,2))                                               AS QuotaRoadPerc,
    CAST(100.0 * FatturatoTouring / NULLIF(FatturatoBici, 0)
         AS DECIMAL(5,2))                                               AS QuotaTouringPerc
FROM PerPaese
ORDER BY Fatturato DESC;

/*
FATTI (2013)
- Il margine % va dal 40,14% dell'Australia al 43,18% del Canada: 3 punti di differenza.
- Il prezzo medio delle bici è simile ovunque (da 1.546,86 a 1.623,42): non è il prezzo
  a fare la differenza.
- Cambia il mix. Le Mountain pesano il 48,07% negli Stati Uniti e il 47,44% in Canada, ma
  solo il 30,21% in Australia, dove le Road sono al 45,93% (negli altri paesi tra 23,77%
  e 34,48%). Le Touring sono simili ovunque (tra 22,79% e 28,79%).
- In Canada le bici sono solo l'86,46% del fatturato: accessori e abbigliamento valgono
  il 13,54%, contro il 4,6-6,8% degli altri paesi.
- Verifica: applicando al mix di ogni paese i margini del file 01 (Mountain 45,45%,
  Road 36,36%, Touring 37,84%, non-bici 55,24%) si ottiene quasi il margine reale:
  Australia 40,19% (reale 40,14%), Stati Uniti 42,07% (42,10%), Canada 43,01% (43,18%).

CONCLUSIONE
- Le differenze di margine tra paesi sono un effetto mix: più Mountain e più accessori
  alzano il margine, più Road lo abbassano. Non dipendono da prezzi o costi diversi per paese.
*/


-- ---------------------------------------------------------------------
-- 2.3 Perché nel 2012 il fatturato cala in Nord America e Australia ma cresce in Europa?
--     Scompongo la variazione del fatturato bici in pezzi venduti e prezzo medio,
--     e misuro quanto pesavano nel 2011 i due modelli premium usciti dal catalogo.
-- ---------------------------------------------------------------------

-- Passo 1: pezzi e fatturato delle bici per paese, con 2011 e 2012 in colonna
WITH PerPaese AS (
    SELECT
        t.SalesTerritoryCountry                                         AS Paese,
        SUM(CASE WHEN d.CalendarYear = 2011 THEN f.OrderQuantity ELSE 0 END)    AS Pezzi2011,
        SUM(CASE WHEN d.CalendarYear = 2012 THEN f.OrderQuantity ELSE 0 END)    AS Pezzi2012,
        SUM(CASE WHEN d.CalendarYear = 2011 THEN f.SalesAmount   ELSE 0 END)    AS Fatturato2011,
        SUM(CASE WHEN d.CalendarYear = 2012 THEN f.SalesAmount   ELSE 0 END)    AS Fatturato2012,
        SUM(CASE WHEN d.CalendarYear = 2011
                  AND p.ModelName IN ('Road-150', 'Mountain-100')
                 THEN f.SalesAmount ELSE 0 END)                         AS FatturatoPremium2011
    FROM dbo.FactInternetSales      AS f
    JOIN dbo.DimDate                AS d   ON f.OrderDateKey          = d.DateKey
    JOIN dbo.DimSalesTerritory      AS t   ON f.SalesTerritoryKey     = t.SalesTerritoryKey
    JOIN dbo.DimProduct             AS p   ON f.ProductKey            = p.ProductKey
    JOIN dbo.DimProductSubcategory  AS ps  ON p.ProductSubcategoryKey = ps.ProductSubcategoryKey
    JOIN dbo.DimProductCategory     AS pc  ON ps.ProductCategoryKey   = pc.ProductCategoryKey
    WHERE pc.EnglishProductCategoryName = 'Bikes'
      AND d.CalendarYear IN (2011, 2012)
    GROUP BY t.SalesTerritoryCountry
)

-- Passo 2: variazioni di pezzi, prezzo medio e fatturato, e peso dei modelli premium nel 2011
SELECT
    Paese,
    Pezzi2011,
    Pezzi2012,
    CAST(100.0 * (Pezzi2012 - Pezzi2011) / Pezzi2011
         AS DECIMAL(7,2))                                               AS VarPezziPerc,
    CAST(Fatturato2011 / Pezzi2011 AS DECIMAL(10,2))                    AS PrezzoMedio2011,
    CAST(Fatturato2012 / Pezzi2012 AS DECIMAL(10,2))                    AS PrezzoMedio2012,
    CAST(100.0 * (Fatturato2012 / Pezzi2012 - Fatturato2011 / Pezzi2011)
         / (Fatturato2011 / Pezzi2011) AS DECIMAL(7,2))                 AS VarPrezzoMedioPerc,
    CAST(100.0 * (Fatturato2012 - Fatturato2011) / Fatturato2011
         AS DECIMAL(7,2))                                               AS VarFatturatoPerc,
    CAST(100.0 * FatturatoPremium2011 / Fatturato2011
         AS DECIMAL(5,2))                                               AS QuotaPremium2011Perc
FROM PerPaese
ORDER BY VarFatturatoPerc;

/*
FATTI
- Controllo: i pezzi sommano 2.216 nel 2011 e 3.269 nel 2012, come nel file 01.
- Nel 2011 i due modelli premium pesano allo stesso modo in tutti i paesi: tra il 94,46%
  e il 98,30% del fatturato bici.
- Il prezzo medio cala ovunque in misura simile: dal -38,53% della Francia al -48,10%
  degli Stati Uniti.
- La differenza è nei pezzi venduti. Francia +156,43%, Regno Unito +131,43% e Germania
  +93,71% (Europa nel complesso da 490 a 1.103 pezzi, +125%); Australia +43,77%;
  Stati Uniti +12,60% e Canada -0,59% (Nord America da 940 a 1.036 pezzi, +10%).
- Con un prezzo medio quasi dimezzato servono circa il doppio dei pezzi per mantenere il
  fatturato: ci riesce solo l'Europa.

CONCLUSIONE
- L'ipotesi fatta nella 2.1 non è confermata: i modelli premium non pesavano di più in
  Nord America. L'effetto mix è uguale in tutti i paesi; quello che cambia è la crescita
  dei volumi, forte in Europa e quasi ferma in Nord America.

IPOTESI
- I paesi europei partono da volumi piccoli (tra 140 e 175 bici nel 2011): potrebbero essere
  mercati più giovani, ancora in fase di crescita.
*/


-- =====================================================================
-- 3. STAGIONALITÀ PER EMISFERO
-- =====================================================================

-- ---------------------------------------------------------------------
-- 3.1 Il picco di giugno c'è in entrambi gli emisferi? (2011-2013)
--     Emisfero sud = Australia, emisfero nord = tutti gli altri paesi
--     (i paesi con vendite sono i sei della query 1.1).
-- ---------------------------------------------------------------------

-- Passo 1: fatturato per anno e mese, diviso tra i due emisferi
WITH PerMese AS (
    SELECT
        d.CalendarYear                                                  AS Anno,
        d.MonthNumberOfYear                                             AS Mese,
        d.EnglishMonthName                                              AS NomeMese,
        SUM(CASE WHEN t.SalesTerritoryCountry <> 'Australia'
                 THEN f.SalesAmount ELSE 0 END)                         AS FatturatoNord,
        SUM(CASE WHEN t.SalesTerritoryCountry =  'Australia'
                 THEN f.SalesAmount ELSE 0 END)                         AS FatturatoSud
    FROM dbo.FactInternetSales      AS f
    JOIN dbo.DimDate                AS d   ON f.OrderDateKey      = d.DateKey
    JOIN dbo.DimSalesTerritory      AS t   ON f.SalesTerritoryKey = t.SalesTerritoryKey
    WHERE d.CalendarYear BETWEEN 2011 AND 2013
    GROUP BY d.CalendarYear, d.MonthNumberOfYear, d.EnglishMonthName
)

-- Passo 2: peso di ogni mese sul fatturato annuo dello stesso emisfero
SELECT
    Anno,
    Mese,
    NomeMese,
    CAST(FatturatoNord AS DECIMAL(12,2))                    AS FatturatoNord,
    CAST(100.0 * FatturatoNord
         / SUM(FatturatoNord) OVER (PARTITION BY Anno)
         AS DECIMAL(5,2))                                   AS QuotaNordPerc,       -- un mese "medio" vale 8,33%
    CAST(FatturatoSud AS DECIMAL(12,2))                     AS FatturatoSud,
    CAST(100.0 * FatturatoSud
         / SUM(FatturatoSud) OVER (PARTITION BY Anno)
         AS DECIMAL(5,2))                                   AS QuotaSudPerc
FROM PerMese
ORDER BY Anno, Mese;

/*
FATTI
- I paesi con vendite sono sei (2.1) e solo l'Australia è nell'emisfero sud.
- Emisfero nord: giugno è un picco in tutti e tre gli anni (10,43% - 9,64% - 10,65%),
  sempre sopra maggio (7,63% - 6,68% - 7,74%) e luglio (8,28% - 6,85% - 8,15%).
- Emisfero sud: giugno è un picco nel 2011 (10,42%, mese più alto dell'anno e quasi identico
  al nord), è appena sopra luglio nel 2012 (9,27% contro 8,93%) e non è più un picco nel 2013
  (8,39%, sotto luglio 9,04% e agosto 10,02%).
- Non c'è una stagionalità rovesciata: in Australia gennaio e febbraio, mesi estivi, non sono
  più forti (gennaio 8,08% - 5,82% - 5,25%; febbraio 7,96% - 6,63% - 4,04%).
- Il gennaio-febbraio 2012 forte visto nel file 01 viene solo dal nord (10,00% e 9,85%,
  contro 5,82% e 6,63% del sud).
- Nel 2013 il secondo semestre vale circa il 59% dell'anno in entrambi gli emisferi;
  nel 2012 il 59% a sud e il 51% a nord.
- Controllo: nel 2011 nord (4.511.793,69) + sud (2.563.732,25) = fatturato 2011 del file 01.

IPOTESI
- Il picco di giugno non dipende dal clima: nel 2011 è identico nei due emisferi, dove giugno
  cade in stagioni opposte. È più probabile una caratteristica del dataset di esempio.
- Il secondo semestre più forte nel 2012 e nel 2013 è soprattutto crescita in corso d'anno,
  non stagionalità.

DECISIONE
- Nella dashboard mostro l'andamento mensile, ma senza una lettura "per stagione".
*/


/* =====================================================================
   4. SINTESI DELLE SCOPERTE
   =====================================================================
   1. Si vende in sei paesi e tre macro-aree quasi alla pari (North America 38,68%,
      Pacific 30,86%, Europe 30,46%). Stati Uniti e Australia fanno il 62,8% del fatturato;
      negli Stati Uniti le vendite online sono quasi tutte a ovest.
   2. L'Australia ha meno della metà dei clienti degli Stati Uniti ma spende il doppio
      per cliente (2.549,13 contro 1.239,56).
   3. Il calo del 2012 riguarda Nord America e Australia, mentre l'Europa cresce. Il prezzo
      medio delle bici quasi si dimezza ovunque; la differenza è nei pezzi venduti, che in
      Europa più che raddoppiano e in Nord America restano quasi fermi.
   4. Il margine % è simile in tutti i paesi (tra 40,66% e 41,89% sul 2011-2013): le piccole
      differenze sono un effetto mix tra Mountain, Road e accessori.
   5. Il picco di giugno non dipende dal clima: nel 2011 è identico nei due emisferi e non
      c'è una stagionalità rovesciata in Australia.

   Decisioni per il modello
   - Geografia su tre livelli (gruppo, paese, regione), con analisi per paese.
   - Il territorio della vendita coincide sempre con quello del cliente.
   - Nessuna dimensione valuta: gli importi non sono convertiti e si sommano tra paesi.
   - Prodotti da raggruppare per modello, non per ProductKey.

   Limiti del dataset (dati di esempio)
   - Tre regioni degli Stati Uniti quasi senza vendite online.
   - CurrencyKey non segue il paese (Francia e Germania comprano per il 98% in dollari USA).
   - Nessuna stagionalità legata al clima: il picco di giugno 2011 è uguale nei due emisferi.
   ===================================================================== */
