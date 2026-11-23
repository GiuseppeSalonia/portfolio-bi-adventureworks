/* =====================================================================
   PORTFOLIO BI - ADVENTUREWORKS
   File 04 - Canale rivenditori e confronto con il canale online
   ---------------------------------------------------------------------
   Database : AdventureWorksDW2025 su SQL Server 2025
   Canali   : Rivenditori (FactResellerSales) e Internet (FactInternetSales)
   Scopo    : capire quanto pesa il secondo canale, in cosa è diverso dall'online
              e decidere se includerlo nel modello di Power BI.

   Contenuto
     1. Panoramica del canale rivenditori e controlli
     2. Confronto tra i due canali
     3. Bici: modelli premium e prezzi nei due canali
     4. Sconti e promozioni
     5. Tipi di rivenditore
     6. Sintesi delle scoperte

   Definizioni: le stesse del file 01 (Fatturato = SalesAmount,
   Margine lordo = SalesAmount - TotalProductCost, anni completi 2011-2013).

   I numeri citati nei commenti sono i risultati delle query di questo file.
   ===================================================================== */

USE AdventureWorksDW2025;
GO


-- =====================================================================
-- 1. PANORAMICA DEL CANALE RIVENDITORI E CONTROLLI
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1.1 Quanto è grande la tabella dei rivenditori e quale periodo copre?
-- ---------------------------------------------------------------------
SELECT
    COUNT(*)                            AS RigheVendita,
    COUNT(DISTINCT SalesOrderNumber)    AS NumeroOrdini,
    COUNT(DISTINCT ResellerKey)         AS NumeroRivenditori,
    COUNT(DISTINCT EmployeeKey)         AS NumeroVenditori,
    COUNT(DISTINCT ProductKey)          AS NumeroProdotti,
    CAST(MIN(OrderDate) AS DATE)        AS PrimoOrdine,
    CAST(MAX(OrderDate) AS DATE)        AS UltimoOrdine
FROM dbo.FactResellerSales;

/*
FATTI
- 60.855 righe di vendita, 3.796 ordini (in media 16 righe per ordine), 635 rivenditori
  serviti da 17 venditori, 334 prodotti venduti (online erano 158).
- Primo ordine il 29 dicembre 2010, ultimo il 29 novembre 2013: rispetto all'online mancano
  dicembre 2013 e gennaio 2014.
- In DimReseller ci sono 701 rivenditori: 66 non hanno mai comprato.
*/


-- ---------------------------------------------------------------------
-- 1.2 Controllo di qualità: collegando le dimensioni perdo righe di vendita?
--     (stesso controllo del file 01, query 1.5, con in più il rivenditore)
-- ---------------------------------------------------------------------
SELECT
    COUNT(*)                        AS RigheVendita,
    COUNT(d.DateKey)                AS RigheConData,
    COUNT(r.ResellerKey)            AS RigheConRivenditore,
    COUNT(ps.ProductSubcategoryKey) AS RigheConSottocategoria,
    COUNT(pc.ProductCategoryKey)    AS RigheConCategoria
FROM dbo.FactResellerSales          AS f
LEFT JOIN dbo.DimDate               AS d   ON f.OrderDateKey          = d.DateKey
LEFT JOIN dbo.DimReseller           AS r   ON f.ResellerKey           = r.ResellerKey
LEFT JOIN dbo.DimProduct            AS p   ON f.ProductKey            = p.ProductKey
LEFT JOIN dbo.DimProductSubcategory AS ps  ON p.ProductSubcategoryKey = ps.ProductSubcategoryKey
LEFT JOIN dbo.DimProductCategory    AS pc  ON ps.ProductCategoryKey   = pc.ProductCategoryKey;

/*
FATTO
- I cinque numeri coincidono (60.855): ogni riga ha data, rivenditore, sottocategoria e
  categoria. Posso usare JOIN normali senza perdere vendite.
*/


-- =====================================================================
-- 2. CONFRONTO TRA I DUE CANALI
--    Le due tabelle dei fatti hanno le stesse colonne di vendita: con UNION ALL
--    le metto una sotto l'altra e aggiungo una colonna che dice da quale canale
--    arriva ogni riga.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 2.1 Quanto vende ogni canale, anno per anno, e con quale margine?
-- ---------------------------------------------------------------------

-- Passo 1: le vendite dei due canali in un'unica tabella
WITH Vendite AS (
    SELECT 'Internet'    AS Canale, OrderDateKey, SalesOrderNumber, OrderQuantity, SalesAmount, TotalProductCost
    FROM dbo.FactInternetSales
    UNION ALL
    SELECT 'Rivenditori' AS Canale, OrderDateKey, SalesOrderNumber, OrderQuantity, SalesAmount, TotalProductCost
    FROM dbo.FactResellerSales
),

-- Passo 2: totali per anno e canale
PerAnnoCanale AS (
    SELECT
        d.CalendarYear                              AS Anno,
        v.Canale,
        COUNT(DISTINCT d.MonthNumberOfYear)         AS MesiConVendite,
        COUNT(DISTINCT v.SalesOrderNumber)          AS NumeroOrdini,
        SUM(v.OrderQuantity)                        AS PezziVenduti,
        SUM(v.SalesAmount)                          AS Fatturato,
        SUM(v.SalesAmount - v.TotalProductCost)     AS Margine
    FROM Vendite        AS v
    JOIN dbo.DimDate    AS d   ON v.OrderDateKey = d.DateKey
    GROUP BY d.CalendarYear, v.Canale
)

-- Passo 3: margine %, valore medio dell'ordine e peso del canale sul totale dell'anno
SELECT
    Anno,
    Canale,
    MesiConVendite,
    NumeroOrdini,
    PezziVenduti,
    CAST(Fatturato AS DECIMAL(12,2))                        AS Fatturato,
    CAST(Margine   AS DECIMAL(12,2))                        AS Margine,
    CAST(100.0 * Margine / Fatturato AS DECIMAL(5,2))       AS MarginePerc,
    CAST(Fatturato / NumeroOrdini AS DECIMAL(12,2))         AS ValoreMedioOrdine,
    CAST(100.0 * Fatturato
         / SUM(Fatturato) OVER (PARTITION BY Anno)
         AS DECIMAL(5,2))                                   AS QuotaCanalePerc
FROM PerAnnoCanale
ORDER BY Anno, Canale;

/*
FATTI
- Controllo: le righe "Internet" coincidono con il file 01 (per esempio 2011: 2.216 ordini,
  7.075.525,93 di fatturato, margine 40,20%). L'unione dei canali non altera i numeri.
- I rivenditori sono il canale principale per fatturato: nel 2011-2013 fanno 79,96 milioni
  contro 29,27 dell'online, cioè il 73,2% del totale (109,23 milioni).
- Il margine lordo è quasi nullo: 0,16% nel 2011, 3,25% nel 2012 e -1,46% nel 2013.
  Sul 2011-2013 i rivenditori portano 453.449,17 di margine (0,57%), l'online 12.037.481,74
  (41,13%). L'online fa il 26,8% del fatturato e il 96,4% del margine lordo.
- Un ordine dei rivenditori vale in media circa 20.000 (da 19.657,40 a 23.535,32), contro
  i 768-3.193 dell'online.
- ATTENZIONE: i rivenditori non hanno vendite in tutti i mesi. Il 2011 ne ha 9 su 12 e
  il 2013 ne ha 11. Solo il 2012 ha tutti i mesi (dettaglio nella query 2.3).

IPOTESI
- Un margine vicino a zero sul canale principale dipende da come è costruito il dataset:
  il costo usato è il costo standard del prodotto e i prezzi ai rivenditori sono molto
  vicini a quel costo. In un'azienda reale sarebbe il primo tema da portare alla direzione.
*/


-- ---------------------------------------------------------------------
-- 2.2 Cosa vende ogni canale? Categorie, peso sul canale e margine (2011-2013)
-- ---------------------------------------------------------------------

-- Passo 1: le vendite dei due canali in un'unica tabella
WITH Vendite AS (
    SELECT 'Internet'    AS Canale, OrderDateKey, ProductKey, OrderQuantity, SalesAmount, TotalProductCost
    FROM dbo.FactInternetSales
    UNION ALL
    SELECT 'Rivenditori' AS Canale, OrderDateKey, ProductKey, OrderQuantity, SalesAmount, TotalProductCost
    FROM dbo.FactResellerSales
),

-- Passo 2: totali per canale e categoria
PerCategoria AS (
    SELECT
        v.Canale,
        pc.EnglishProductCategoryName               AS Categoria,
        SUM(v.OrderQuantity)                        AS PezziVenduti,
        SUM(v.SalesAmount)                          AS Fatturato,
        SUM(v.SalesAmount - v.TotalProductCost)     AS Margine
    FROM Vendite                    AS v
    JOIN dbo.DimDate                AS d   ON v.OrderDateKey          = d.DateKey
    JOIN dbo.DimProduct             AS p   ON v.ProductKey            = p.ProductKey
    JOIN dbo.DimProductSubcategory  AS ps  ON p.ProductSubcategoryKey = ps.ProductSubcategoryKey
    JOIN dbo.DimProductCategory     AS pc  ON ps.ProductCategoryKey   = pc.ProductCategoryKey
    WHERE d.CalendarYear BETWEEN 2011 AND 2013
    GROUP BY v.Canale, pc.EnglishProductCategoryName
)

-- Passo 3: peso della categoria sul fatturato del suo canale e margine %
SELECT
    Canale,
    Categoria,
    PezziVenduti,
    CAST(Fatturato AS DECIMAL(12,2))                        AS Fatturato,
    CAST(100.0 * Fatturato
         / SUM(Fatturato) OVER (PARTITION BY Canale)
         AS DECIMAL(5,2))                                   AS QuotaSulCanalePerc,
    CAST(Margine AS DECIMAL(12,2))                          AS Margine,
    CAST(100.0 * Margine / Fatturato AS DECIMAL(5,2))       AS MarginePerc
FROM PerCategoria
ORDER BY Canale, Fatturato DESC;

/*
FATTI (2011-2013)
- Controlli: le categorie sommano 29.269.561,46 per l'online e 79.961.268,41 per i
  rivenditori, come nella query 2.1.
- I rivenditori vendono anche i Components (14,72% del loro fatturato), che online non esistono.
- Le bici sono l'82,35% del fatturato dei rivenditori ma hanno margine negativo: -1,53%,
  cioè una perdita lorda di 1.005.603,45. I Components la compensano quasi esattamente
  (+1.031.357,98, margine 8,76%).
- I rivenditori comprano 74.560 bici contro le 15.191 dell'online (4,9 volte), ma il
  fatturato bici è solo 2,3 volte: i prezzi sono molto più bassi (vedi 3.2).
- Lo stesso prodotto rende meno ai rivenditori: Accessories 34,25% contro 62,60% online,
  Clothing 13,10% contro 40,03%.
*/


-- ---------------------------------------------------------------------
-- 2.3 In quali mesi vende ogni canale? (2011-2013)
--     Serve a capire quali anni dei rivenditori sono confrontabili: nella 2.1 il 2011
--     ha vendite in 9 mesi e il 2013 in 11.
-- ---------------------------------------------------------------------

-- Passo 1: le vendite dei due canali in un'unica tabella
WITH Vendite AS (
    SELECT 'Internet'    AS Canale, OrderDateKey, SalesOrderNumber, SalesAmount
    FROM dbo.FactInternetSales
    UNION ALL
    SELECT 'Rivenditori' AS Canale, OrderDateKey, SalesOrderNumber, SalesAmount
    FROM dbo.FactResellerSales
),

-- Passo 2: ordini e fatturato per anno, mese e canale
PerMeseCanale AS (
    SELECT
        d.CalendarYear                              AS Anno,
        d.MonthNumberOfYear                         AS Mese,
        v.Canale,
        COUNT(DISTINCT v.SalesOrderNumber)          AS NumeroOrdini,
        SUM(v.SalesAmount)                          AS Fatturato
    FROM Vendite        AS v
    JOIN dbo.DimDate    AS d   ON v.OrderDateKey = d.DateKey
    WHERE d.CalendarYear BETWEEN 2011 AND 2013
    GROUP BY d.CalendarYear, d.MonthNumberOfYear, v.Canale
),

-- Passo 3: l'elenco completo dei 36 mesi, preso dal calendario
Mesi AS (
    SELECT DISTINCT
        CalendarYear                                AS Anno,
        MonthNumberOfYear                           AS Mese
    FROM dbo.DimDate
    WHERE CalendarYear BETWEEN 2011 AND 2013
)

-- Passo 4: un mese per riga con i due canali in colonna.
--          LEFT JOIN dal calendario: un mese senza vendite resta visibile, con zero.
SELECT
    m.Anno,
    m.Mese,
    COALESCE(i.NumeroOrdini, 0)                             AS OrdiniInternet,
    CAST(COALESCE(i.Fatturato, 0) AS DECIMAL(12,2))         AS FatturatoInternet,
    COALESCE(r.NumeroOrdini, 0)                             AS OrdiniRivenditori,
    CAST(COALESCE(r.Fatturato, 0) AS DECIMAL(12,2))         AS FatturatoRivenditori
FROM Mesi                   AS m
LEFT JOIN PerMeseCanale     AS i
    ON  i.Anno = m.Anno AND i.Mese = m.Mese AND i.Canale = 'Internet'
LEFT JOIN PerMeseCanale     AS r
    ON  r.Anno = m.Anno AND r.Mese = m.Mese AND r.Canale = 'Rivenditori'
ORDER BY m.Anno, m.Mese;

/*
FATTI
- Controllo: i mesi dei rivenditori sommano ai totali annui della query 2.1
  (18.192.802,70 nel 2011, 28.193.631,52 nel 2012, 33.574.834,14 nel 2013, a meno di
  qualche centesimo di arrotondamento).
- L'online ha vendite in tutti i 36 mesi.
- Rivenditori 2011: nessun ordine a febbraio, aprile e giugno; da luglio in poi si ordina
  ogni mese. L'anno copre comunque tutto il periodo gennaio-dicembre.
- Rivenditori 2012: tutti i 12 mesi. Rivenditori 2013: manca dicembre, perché i dati si
  fermano al 29 novembre.
- Nel 2012 e nel 2013 marzo, giugno e settembre sono i mesi con meno ordini (2012: 73, 65
  e 74 contro 94-139 degli altri mesi; 2013: 99, 94 e 93 contro 174-185). Giugno, che online
  è un picco, per i rivenditori è un mese debole.
- Confronto alla pari su gennaio-novembre 2013: online 14,48 milioni, rivenditori 33,57.
  La quota dei rivenditori è il 69,87%, contro il 67,25% calcolato sull'anno intero.

IPOTESI
- I rivenditori ordinano a cadenza fissa: ogni due mesi all'inizio del 2011, poi con un
  ciclo trimestrale. Si può verificare con la colonna OrderFrequency di DimReseller.

DECISIONE
- Per i rivenditori 2011 e 2012 sono anni interi, il 2013 è senza dicembre: nei confronti
  tra canali del 2013 lo segnalo.
- L'andamento mensile dei rivenditori descrive la cadenza degli ordini, non una stagionalità.
*/


-- =====================================================================
-- 3. BICI: MODELLI PREMIUM E PREZZI NEI DUE CANALI
-- =====================================================================

-- ---------------------------------------------------------------------
-- 3.1 Road-150 e Mountain-100, spariti dall'online dopo il 2011, si vendono
--     ancora ai rivenditori? (tutti gli anni)
-- ---------------------------------------------------------------------

-- Passo 1: le vendite dei due canali in un'unica tabella
WITH Vendite AS (
    SELECT 'Internet'    AS Canale, OrderDateKey, ProductKey, OrderQuantity, SalesAmount, TotalProductCost
    FROM dbo.FactInternetSales
    UNION ALL
    SELECT 'Rivenditori' AS Canale, OrderDateKey, ProductKey, OrderQuantity, SalesAmount, TotalProductCost
    FROM dbo.FactResellerSales
)

-- Passo 2: pezzi, prezzo medio e margine dei due modelli per canale e anno
SELECT
    p.ModelName                                             AS Modello,
    v.Canale,
    d.CalendarYear                                          AS Anno,
    SUM(v.OrderQuantity)                                    AS PezziVenduti,
    CAST(SUM(v.SalesAmount) AS DECIMAL(12,2))               AS Fatturato,
    CAST(SUM(v.SalesAmount) / SUM(v.OrderQuantity)
         AS DECIMAL(10,2))                                  AS PrezzoMedio,
    CAST(100.0 * SUM(v.SalesAmount - v.TotalProductCost)
         / SUM(v.SalesAmount) AS DECIMAL(6,2))              AS MarginePerc
FROM Vendite            AS v
JOIN dbo.DimDate        AS d   ON v.OrderDateKey = d.DateKey
JOIN dbo.DimProduct     AS p   ON v.ProductKey   = p.ProductKey
WHERE p.ModelName IN ('Road-150', 'Mountain-100')
GROUP BY p.ModelName, v.Canale, d.CalendarYear
ORDER BY Modello, Canale, Anno;

/*
FATTI
- No: Road-150 e Mountain-100 si vendono solo nel 2010 e nel 2011 in entrambi i canali.
  Dopo il 2011 escono dal catalogo, non si spostano sui rivenditori.
- La Mountain-100 era soprattutto un prodotto da rivenditori (4.438 pezzi nel 2011 contro
  391 online), la Road-150 soprattutto da online (1.544 contro 1.084).
- Ai rivenditori la Road-150 costa 2.146,96 contro 3.578,27 online: esattamente il 60% del
  prezzo al pubblico. La Mountain-100 è al 55% (1.877,31 contro 3.386,56).
- Con questi prezzi il margine sui rivenditori è nullo o negativo (-1,13% e -1,46% nel 2011),
  contro il 39,32% e il 43,76% dell'online.
- Le Road-150 vendute online sono 1.551 (7 + 1.544): lo stesso numero delle righe con motivo
  d'acquisto "Quality" del file 03.
*/


-- ---------------------------------------------------------------------
-- 3.2 A che prezzo si vendono le bici ai rivenditori rispetto all'online? (2011-2013)
--     I due canali diventano colonne con SUM(CASE WHEN ...): una riga per anno e linea.
-- ---------------------------------------------------------------------

-- Passo 1: le vendite dei due canali in un'unica tabella
WITH Vendite AS (
    SELECT 'Internet'    AS Canale, OrderDateKey, ProductKey, OrderQuantity, SalesAmount
    FROM dbo.FactInternetSales
    UNION ALL
    SELECT 'Rivenditori' AS Canale, OrderDateKey, ProductKey, OrderQuantity, SalesAmount
    FROM dbo.FactResellerSales
),

-- Passo 2: pezzi e fatturato delle bici per anno e linea, con i due canali in colonna
PerLinea AS (
    SELECT
        d.CalendarYear                                                          AS Anno,
        ps.EnglishProductSubcategoryName                                        AS Sottocategoria,
        SUM(CASE WHEN v.Canale = 'Internet'    THEN v.OrderQuantity ELSE 0 END) AS PezziInternet,
        SUM(CASE WHEN v.Canale = 'Rivenditori' THEN v.OrderQuantity ELSE 0 END) AS PezziRivenditori,
        SUM(CASE WHEN v.Canale = 'Internet'    THEN v.SalesAmount   ELSE 0 END) AS FatturatoInternet,
        SUM(CASE WHEN v.Canale = 'Rivenditori' THEN v.SalesAmount   ELSE 0 END) AS FatturatoRivenditori
    FROM Vendite                    AS v
    JOIN dbo.DimDate                AS d   ON v.OrderDateKey          = d.DateKey
    JOIN dbo.DimProduct             AS p   ON v.ProductKey            = p.ProductKey
    JOIN dbo.DimProductSubcategory  AS ps  ON p.ProductSubcategoryKey = ps.ProductSubcategoryKey
    JOIN dbo.DimProductCategory     AS pc  ON ps.ProductCategoryKey   = pc.ProductCategoryKey
    WHERE pc.EnglishProductCategoryName = 'Bikes'
      AND d.CalendarYear BETWEEN 2011 AND 2013
    GROUP BY d.CalendarYear, ps.EnglishProductSubcategoryName
)

-- Passo 3: prezzo medio nei due canali e differenza in % (NULLIF evita la divisione per zero)
SELECT
    Anno,
    Sottocategoria,
    PezziInternet,
    PezziRivenditori,
    CAST(FatturatoInternet    / NULLIF(PezziInternet, 0)    AS DECIMAL(10,2))   AS PrezzoMedioInternet,
    CAST(FatturatoRivenditori / NULLIF(PezziRivenditori, 0) AS DECIMAL(10,2))   AS PrezzoMedioRivenditori,
    CAST(100.0 * (FatturatoRivenditori / NULLIF(PezziRivenditori, 0)
                  - FatturatoInternet / NULLIF(PezziInternet, 0))
         / (FatturatoInternet / NULLIF(PezziInternet, 0))
         AS DECIMAL(7,2))                                                       AS DifferenzaPrezzoPerc
FROM PerLinea
ORDER BY Anno, Sottocategoria;

/*
FATTI
- In ogni anno e per ogni linea il prezzo medio ai rivenditori è più basso di quello
  online: dal -34,21% (Road 2013) al -76,43% (Road 2011).
- I rivenditori comprano molte più bici: 14.984 nel 2011, 27.951 nel 2012 e 31.625 nel 2013,
  contro 2.216, 3.269 e 9.706 dell'online.
- Le Touring arrivano ai rivenditori prima che online: 806 pezzi nel 2012 contro 13.

ATTENZIONE
- La differenza di prezzo mescola due effetti: lo sconto all'ingrosso (per la Road-150 è
  il 40%, vedi 3.1) e un mix diverso di modelli. Questa query non li separa: per farlo
  bisognerebbe confrontare modello per modello.
*/


-- =====================================================================
-- 4. SCONTI E PROMOZIONI
-- =====================================================================

-- ---------------------------------------------------------------------
-- 4.1 Quali promozioni si usano nei due canali, e quanto costano in sconti e margine?
--     (tutto il periodo)
-- ---------------------------------------------------------------------

-- Passo 1: le vendite dei due canali in un'unica tabella
WITH Vendite AS (
    SELECT 'Internet'    AS Canale, PromotionKey, ExtendedAmount, DiscountAmount, SalesAmount, TotalProductCost
    FROM dbo.FactInternetSales
    UNION ALL
    SELECT 'Rivenditori' AS Canale, PromotionKey, ExtendedAmount, DiscountAmount, SalesAmount, TotalProductCost
    FROM dbo.FactResellerSales
)

-- Passo 2: righe, sconti e margine per canale e promozione
SELECT
    v.Canale,
    pr.EnglishPromotionType                                 AS TipoPromozione,
    pr.EnglishPromotionName                                 AS Promozione,
    COUNT(*)                                                AS RigheVendita,
    CAST(SUM(v.ExtendedAmount) AS DECIMAL(12,2))            AS ImportoListino,
    CAST(SUM(v.DiscountAmount) AS DECIMAL(12,2))            AS Sconti,
    CAST(100.0 * SUM(v.DiscountAmount)
         / NULLIF(SUM(v.ExtendedAmount), 0) AS DECIMAL(5,2)) AS ScontoPerc,
    CAST(SUM(v.SalesAmount) AS DECIMAL(12,2))               AS Fatturato,
    CAST(100.0 * SUM(v.SalesAmount - v.TotalProductCost)
         / NULLIF(SUM(v.SalesAmount), 0) AS DECIMAL(6,2))   AS MarginePerc
FROM Vendite                AS v
JOIN dbo.DimPromotion       AS pr  ON v.PromotionKey = pr.PromotionKey
GROUP BY v.Canale, pr.EnglishPromotionType, pr.EnglishPromotionName
ORDER BY v.Canale, Fatturato DESC;

/*
FATTI
- Controlli: le righe sommano 60.398 per l'online e 60.855 per i rivenditori.
- Online: 2.151 righe (3,56%) hanno una promozione assegnata, ma lo sconto è sempre 0,00.
  La promozione online è solo un'etichetta: prezzo di listino e fatturato coincidono.
- Rivenditori: il 94,61% delle righe è senza sconto. Gli sconti valgono in tutto 527.507,93,
  lo 0,65% dell'importo di listino.
- Anche senza sconti il margine dei rivenditori è basso (3,06%): il margine quasi nullo del
  canale non dipende dalle promozioni ma dai prezzi all'ingrosso.
- Gli sconti per quantità vanno dal 2% al 15% e portano il margine sotto zero
  (da -2,20% a -16,99%).
- Le promozioni su singoli prodotti hanno margini fortemente negativi: da -62,51%
  (Touring-3000) a -354,61% (Mountain-500 Silver Clearance Sale).

PROBLEMA NEI DATI
- Un margine di -246% o -354% non si spiega con uno sconto del 35-40%: vuol dire che il
  costo registrato è tra 3,5 e 4,5 volte il ricavo. Su queste righe prezzo o costo non sono
  coerenti con il resto della tabella. Sono poche (meno di 1.200 righe) e le segnalo come limite.
- La domanda aperta del file 03 resta senza una risposta nei numeri: "On Promotion" è citato
  online nel 12,71% degli ordini, ma nessuna riga online ha uno sconto.
*/


-- =====================================================================
-- 5. TIPI DI RIVENDITORE
-- =====================================================================

-- ---------------------------------------------------------------------
-- 5.1 Che tipi di rivenditore ci sono e quanto vale ciascuno? (2011-2013)
-- ---------------------------------------------------------------------

-- Passo 1: totali per tipo di attività del rivenditore
WITH PerTipo AS (
    SELECT
        r.BusinessType                              AS TipoRivenditore,
        COUNT(DISTINCT f.ResellerKey)               AS NumeroRivenditori,
        COUNT(DISTINCT f.SalesOrderNumber)          AS NumeroOrdini,
        SUM(f.SalesAmount)                          AS Fatturato,
        SUM(f.SalesAmount - f.TotalProductCost)     AS Margine
    FROM dbo.FactResellerSales  AS f
    JOIN dbo.DimDate            AS d   ON f.OrderDateKey = d.DateKey
    JOIN dbo.DimReseller        AS r   ON f.ResellerKey  = r.ResellerKey
    WHERE d.CalendarYear BETWEEN 2011 AND 2013
    GROUP BY r.BusinessType
)

-- Passo 2: quota, margine % e fatturato medio per rivenditore
SELECT
    TipoRivenditore,
    NumeroRivenditori,
    NumeroOrdini,
    CAST(Fatturato AS DECIMAL(12,2))                        AS Fatturato,
    CAST(100.0 * Fatturato / SUM(Fatturato) OVER ()
         AS DECIMAL(5,2))                                   AS QuotaFatturatoPerc,
    CAST(100.0 * Margine / Fatturato AS DECIMAL(5,2))       AS MarginePerc,
    CAST(Fatturato / NumeroRivenditori AS DECIMAL(12,2))    AS FatturatoPerRivenditore
FROM PerTipo
ORDER BY Fatturato DESC;

/*
FATTI (2011-2013)
- Controlli: i tre tipi sommano 635 rivenditori, 3.758 ordini e 79.961.268,41 di fatturato.
- I tre tipi hanno quasi lo stesso numero di rivenditori (219, 216 e 200), ma un peso molto
  diverso: Warehouse 48,14% del fatturato, Value Added Reseller 43,46%, Specialty Bike
  Shop 8,40%.
- Un Warehouse compra in media 175.784,07, un negozio specializzato 33.572,84: 5,2 volte meno.
- Il margine è vicino a zero per tutti: da -0,03% (Warehouse) a 1,26% (Value Added Reseller).
*/


/* =====================================================================
   6. SINTESI DELLE SCOPERTE
   =====================================================================
   1. I rivenditori sono il canale principale per fatturato: 79,96 milioni nel 2011-2013,
      il 73,2% del totale. Ma il margine lordo è quasi nullo (0,57%): l'online, con il 26,8%
      del fatturato, fa il 96,4% del margine.
   2. Ai rivenditori le bici sono in perdita lorda (-1,53%) e i Components, che online non
      esistono, la compensano. Lo stesso prodotto rende molto meno che online.
   3. Road-150 e Mountain-100 escono dal catalogo dopo il 2011 in entrambi i canali.
      Ai rivenditori la Road-150 costava il 60% del prezzo online.
   4. Gli sconti pesano poco (0,65% del listino): il margine basso dipende dai prezzi
      all'ingrosso, non dalle promozioni. Online le promozioni sono solo un'etichetta.
   5. Tre tipi di rivenditore con numeri simili (circa 200 ciascuno), ma i negozi
      specializzati comprano 5,2 volte meno di un Warehouse.
   6. I rivenditori ordinano a cadenza fissa: giugno, picco online, per loro è un mese debole.

   Regole sui dati per questo canale
   - 2011 e 2012 sono anni interi (nel 2011 senza ordini a febbraio, aprile e giugno);
     il 2013 è senza dicembre.

   Limiti del dataset (dati di esempio)
   - Margine lordo quasi nullo sul canale principale.
   - Margini tra -62% e -355% su meno di 1.200 righe in promozione, non spiegabili con gli sconti.
   - Promozioni assegnate a righe online senza alcuno sconto.
   ===================================================================== */
