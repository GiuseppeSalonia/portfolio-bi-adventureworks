/* =====================================================================
   PORTFOLIO BI - ADVENTUREWORKS
   File 05 - Viste per Power BI (fase 2 del progetto)
   ---------------------------------------------------------------------
   Database : AdventureWorksDW2025 su SQL Server 2025
   Canale   : Internet (il canale rivenditori resta fuori dal modello: vedi file 04)
   Scopo    : preparare le tabelle del modello a stella. Power BI leggerà solo queste
              viste, mai le tabelle originali.

   Modello a stella
     dbo.vw_Vendite       tabella dei fatti: una riga per ogni riga d'ordine
     dbo.vw_Calendario    dimensione: una riga per giorno
     dbo.vw_Prodotti      dimensione: una riga per prodotto venduto online
     dbo.vw_Clienti       dimensione: una riga per cliente
     dbo.vw_Territori     dimensione: una riga per territorio di vendita

   Scelte fatte in base all'esplorazione (file 01-04)
     - Le viste non aggregano: i dati restano riga per riga e i calcoli (quote, variazioni,
       margine %) si fanno con le misure DAX.
     - Il margine per riga è già calcolato: Margine = SalesAmount - TotalProductCost.
     - Nomi di colonna in italiano e senza spazi; le chiavi iniziano tutte con "Chiave".
     - Niente valuta (gli importi non sono convertiti), niente sconti (sempre zero online),
       niente motivi d'acquisto (relazione molti-a-molti, poco informativi).
     - Nella vista clienti non ci sono nome, email, telefono e indirizzo: per l'analisi
       non servono.

   Come si usa
     1. Eseguire tutto il file (F5): crea o aggiorna le cinque viste.
     2. Guardare i quattro risultati della sezione 6 e confrontarli con i valori attesi.
   ===================================================================== */

USE AdventureWorksDW2025;
GO


-- =====================================================================
-- 1. CALENDARIO
--    Solo gli anni con vendite (2010-2014), interi: Power BI vuole un calendario senza buchi.
--    AnnoCompleto = 1 per 2011, 2012 e 2013: serve per filtrare i confronti tra anni.
-- =====================================================================
CREATE OR ALTER VIEW dbo.vw_Calendario
AS
SELECT
    d.DateKey                                               AS ChiaveData,      -- intero AAAAMMGG
    d.FullDateAlternateKey                                  AS Data,
    d.CalendarYear                                          AS Anno,
    d.CalendarQuarter                                       AS Trimestre,
    d.MonthNumberOfYear                                     AS NumeroMese,      -- per ordinare i nomi dei mesi
    CASE d.MonthNumberOfYear
        WHEN  1 THEN 'Gennaio'    WHEN  2 THEN 'Febbraio'   WHEN  3 THEN 'Marzo'
        WHEN  4 THEN 'Aprile'     WHEN  5 THEN 'Maggio'     WHEN  6 THEN 'Giugno'
        WHEN  7 THEN 'Luglio'     WHEN  8 THEN 'Agosto'     WHEN  9 THEN 'Settembre'
        WHEN 10 THEN 'Ottobre'    WHEN 11 THEN 'Novembre'   WHEN 12 THEN 'Dicembre'
    END                                                     AS Mese,
    d.CalendarYear * 100 + d.MonthNumberOfYear              AS AnnoMese,        -- es. 201306
    CASE WHEN d.CalendarYear BETWEEN 2011 AND 2013
         THEN 1 ELSE 0 END                                  AS AnnoCompleto
FROM dbo.DimDate AS d
WHERE d.CalendarYear BETWEEN 2010 AND 2014;
GO


-- =====================================================================
-- 2. PRODOTTI
--    Le tre tabelle prodotto-sottocategoria-categoria diventano una sola dimensione.
--    Solo i prodotti venduti online. Per raggruppare si usa Modello, non la chiave:
--    lo stesso modello ha più chiavi (taglie, colori e cambi di prezzo).
-- =====================================================================
CREATE OR ALTER VIEW dbo.vw_Prodotti
AS
SELECT
    p.ProductKey                            AS ChiaveProdotto,
    p.EnglishProductName                    AS Prodotto,
    p.ModelName                             AS Modello,
    ps.EnglishProductSubcategoryName        AS Sottocategoria,
    pc.EnglishProductCategoryName           AS Categoria,
    p.Color                                 AS Colore
FROM dbo.DimProduct             AS p
JOIN dbo.DimProductSubcategory  AS ps  ON p.ProductSubcategoryKey = ps.ProductSubcategoryKey
JOIN dbo.DimProductCategory     AS pc  ON ps.ProductCategoryKey   = pc.ProductCategoryKey
WHERE EXISTS (                                              -- tiene solo i prodotti con almeno una vendita online
    SELECT 1
    FROM dbo.FactInternetSales AS f
    WHERE f.ProductKey = p.ProductKey
);
GO


-- =====================================================================
-- 3. CLIENTI
--    Anagrafica con città e stato, professione, reddito e due colonne calcolate dalle vendite:
--    TipoCliente (la segmentazione principale emersa nei file 01 e 03) e la data del primo ordine.
-- =====================================================================
CREATE OR ALTER VIEW dbo.vw_Clienti
AS
-- Passo 1: una riga per cliente con il primo ordine e l'indicazione se ha comprato bici
WITH RiepilogoCliente AS (
    SELECT
        f.CustomerKey,
        CAST(MIN(f.OrderDate) AS DATE)                          AS DataPrimoOrdine,
        MAX(CASE WHEN pc.EnglishProductCategoryName = 'Bikes'
                 THEN 1 ELSE 0 END)                             AS HaCompratoBici
    FROM dbo.FactInternetSales      AS f
    JOIN dbo.DimProduct             AS p   ON f.ProductKey            = p.ProductKey
    JOIN dbo.DimProductSubcategory  AS ps  ON p.ProductSubcategoryKey = ps.ProductSubcategoryKey
    JOIN dbo.DimProductCategory     AS pc  ON ps.ProductCategoryKey   = pc.ProductCategoryKey
    GROUP BY f.CustomerKey
)
-- Passo 2: anagrafica del cliente con le colonne calcolate
SELECT
    c.CustomerKey                                               AS ChiaveCliente,
    g.City                                                      AS Citta,
    g.StateProvinceName                                         AS StatoProvincia,
    c.EnglishOccupation                                         AS Professione,
    c.YearlyIncome                                              AS RedditoAnnuo,
    CASE
        WHEN c.YearlyIncome <  40000 THEN '1. meno di 40.000'
        WHEN c.YearlyIncome <  70000 THEN '2. da 40.000 a 69.999'
        WHEN c.YearlyIncome < 100000 THEN '3. da 70.000 a 99.999'
        ELSE                              '4. da 100.000 in su'
    END                                                         AS FasciaReddito,
    CASE WHEN r.HaCompratoBici = 1
         THEN 'Con bici' ELSE 'Solo accessori' END              AS TipoCliente,
    r.DataPrimoOrdine,
    YEAR(r.DataPrimoOrdine)                                     AS AnnoPrimoOrdine
FROM dbo.DimCustomer        AS c
JOIN dbo.DimGeography       AS g   ON c.GeographyKey = g.GeographyKey
JOIN RiepilogoCliente       AS r   ON c.CustomerKey  = r.CustomerKey;
GO


-- =====================================================================
-- 4. TERRITORI
--    Tre livelli: Gruppo > Paese > Regione. Escludo la riga segnaposto "NA", senza vendite.
--    Il paese si legge da qui (file 02: il territorio della vendita coincide sempre
--    con quello del cliente).
-- =====================================================================
CREATE OR ALTER VIEW dbo.vw_Territori
AS
SELECT
    t.SalesTerritoryKey         AS ChiaveTerritorio,
    t.SalesTerritoryGroup       AS Gruppo,
    t.SalesTerritoryCountry     AS Paese,
    t.SalesTerritoryRegion      AS Regione
FROM dbo.DimSalesTerritory AS t
WHERE t.SalesTerritoryCountry <> 'NA';
GO


-- =====================================================================
-- 5. VENDITE (tabella dei fatti)
--    Una riga per ogni riga d'ordine, con le chiavi verso le quattro dimensioni
--    e le misure di base. Nessuna aggregazione.
-- =====================================================================
CREATE OR ALTER VIEW dbo.vw_Vendite
AS
SELECT
    f.SalesOrderNumber                      AS NumeroOrdine,
    f.SalesOrderLineNumber                  AS RigaOrdine,
    f.OrderDateKey                          AS ChiaveData,
    f.ProductKey                            AS ChiaveProdotto,
    f.CustomerKey                           AS ChiaveCliente,
    f.SalesTerritoryKey                     AS ChiaveTerritorio,
    f.OrderQuantity                         AS Quantita,
    f.SalesAmount                           AS Fatturato,
    f.TotalProductCost                      AS Costo,
    f.SalesAmount - f.TotalProductCost      AS Margine
FROM dbo.FactInternetSales AS f;
GO


-- =====================================================================
-- 6. RICONCILIAZIONE
--    Le viste devono restituire gli stessi numeri trovati nell'esplorazione.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 6.1 Quante righe ha ogni vista, e le chiavi delle dimensioni sono uniche?
--     In Power BI una dimensione deve avere una riga per chiave: Righe = ChiaviDistinte.
--     Attesi: Calendario 1.826, Prodotti 158, Clienti 18.484, Territori 10, Vendite 60.398.
-- ---------------------------------------------------------------------
SELECT '1. vw_Calendario' AS Vista, COUNT(*) AS Righe, COUNT(DISTINCT ChiaveData)       AS ChiaviDistinte FROM dbo.vw_Calendario
UNION ALL
SELECT '2. vw_Prodotti',            COUNT(*),          COUNT(DISTINCT ChiaveProdotto)                     FROM dbo.vw_Prodotti
UNION ALL
SELECT '3. vw_Clienti',             COUNT(*),          COUNT(DISTINCT ChiaveCliente)                      FROM dbo.vw_Clienti
UNION ALL
SELECT '4. vw_Territori',           COUNT(*),          COUNT(DISTINCT ChiaveTerritorio)                   FROM dbo.vw_Territori
UNION ALL
SELECT '5. vw_Vendite',             COUNT(*),          COUNT(DISTINCT NumeroOrdine)                       FROM dbo.vw_Vendite
ORDER BY Vista;

-- Per vw_Vendite la colonna ChiaviDistinte conta gli ordini: attesi 27.659.

/*
RISULTATO
- Calendario 1.826, Prodotti 158, Clienti 18.484, Territori 10: in tutte le dimensioni
  righe e chiavi distinte coincidono, quindi ogni chiave compare una volta sola.
- Vendite: 60.398 righe e 27.659 ordini, come nel file 01.
*/


-- ---------------------------------------------------------------------
-- 6.2 Ogni riga di vendita trova la sua riga in tutte e quattro le dimensioni?
--     Attesi: cinque numeri uguali a 60.398.
-- ---------------------------------------------------------------------
SELECT
    COUNT(*)                        AS RigheVendita,
    COUNT(c.ChiaveData)             AS RigheConData,
    COUNT(p.ChiaveProdotto)         AS RigheConProdotto,
    COUNT(k.ChiaveCliente)          AS RigheConCliente,
    COUNT(t.ChiaveTerritorio)       AS RigheConTerritorio
FROM dbo.vw_Vendite             AS v
LEFT JOIN dbo.vw_Calendario     AS c   ON v.ChiaveData       = c.ChiaveData
LEFT JOIN dbo.vw_Prodotti       AS p   ON v.ChiaveProdotto   = p.ChiaveProdotto
LEFT JOIN dbo.vw_Clienti        AS k   ON v.ChiaveCliente    = k.ChiaveCliente
LEFT JOIN dbo.vw_Territori      AS t   ON v.ChiaveTerritorio = t.ChiaveTerritorio;

/*
RISULTATO
- I cinque numeri sono uguali a 60.398: nessuna riga di vendita resta senza data, prodotto,
  cliente o territorio. Aver escluso la riga "NA" dai territori e i prodotti non venduti
  online non fa perdere vendite.
*/


-- ---------------------------------------------------------------------
-- 6.3 I totali per anno coincidono con il file 01 (query 2.1)?
--     Attesi: 2011 = 2.216 ordini e 7.075.525,93; 2012 = 3.269 e 5.842.485,20;
--             2013 = 21.289 e 16.351.550,34, con margine 40,20% - 41,56% - 41,37%.
-- ---------------------------------------------------------------------
SELECT
    c.Anno,
    c.AnnoCompleto,
    COUNT(DISTINCT v.NumeroOrdine)                          AS NumeroOrdini,
    SUM(v.Quantita)                                         AS PezziVenduti,
    CAST(SUM(v.Fatturato) AS DECIMAL(12,2))                 AS Fatturato,
    CAST(SUM(v.Margine)   AS DECIMAL(12,2))                 AS Margine,
    CAST(100.0 * SUM(v.Margine) / SUM(v.Fatturato)
         AS DECIMAL(5,2))                                   AS MarginePerc
FROM dbo.vw_Vendite         AS v
JOIN dbo.vw_Calendario      AS c   ON v.ChiaveData = c.ChiaveData
GROUP BY c.Anno, c.AnnoCompleto
ORDER BY c.Anno;

/*
RISULTATO
- I totali coincidono con il file 01 in tutti e cinque gli anni: 2011 = 2.216 ordini e
  7.075.525,93; 2012 = 3.269 e 5.842.485,20; 2013 = 21.289 e 16.351.550,34; margine
  40,20% - 41,56% - 41,37%.
- AnnoCompleto vale 1 solo per 2011, 2012 e 2013.
*/


-- ---------------------------------------------------------------------
-- 6.4 La segmentazione dei clienti coincide con i file 01 e 03?
--     Attesi: 9.132 clienti "Con bici" e 9.352 "Solo accessori", fatturato totale 29.358.677,23.
-- ---------------------------------------------------------------------
SELECT
    k.TipoCliente,
    COUNT(DISTINCT k.ChiaveCliente)                         AS NumeroClienti,
    COUNT(DISTINCT v.NumeroOrdine)                          AS NumeroOrdini,
    CAST(SUM(v.Fatturato) AS DECIMAL(12,2))                 AS Fatturato,
    CAST(100.0 * SUM(v.Fatturato)
         / SUM(SUM(v.Fatturato)) OVER ()
         AS DECIMAL(5,2))                                   AS QuotaFatturatoPerc
FROM dbo.vw_Vendite     AS v
JOIN dbo.vw_Clienti     AS k   ON v.ChiaveCliente = k.ChiaveCliente
GROUP BY k.TipoCliente
ORDER BY k.TipoCliente;

/*
RISULTATO
- 9.132 clienti "Con bici" e 9.352 "Solo accessori", come nei file 01 e 03. Gli ordini
  sommano 27.659 e il fatturato 29.358.677,22 (un centesimo di arrotondamento).
- Dato nuovo: i clienti con bici fanno il 97,85% del fatturato (28.726.182,08), quelli di
  soli accessori il 2,15% (632.495,14). Conferma la lettura del Pareto nel file 03.

Tutti e quattro i controlli coincidono con i valori attesi: le viste sono pronte per Power BI.
*/
