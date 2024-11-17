-- Remove unwanted decimal numbers and convert into integer for 'balancegross' column
UPDATE loans
SET balancegross = REPLACE(balancegross, '.000', '');

-- Convert 'disbursementgross' column into integer
ALTER TABLE loans ADD COLUMN disbursement_gross INT;

UPDATE loans
SET disbursement_gross = CAST(disbursementgross AS INT);

-- Remove '$', commas, and convert 'balancegross' into integer
UPDATE loans
SET balancegross = REPLACE(REPLACE(balancegross, '.000', ''), ',', '');

ALTER TABLE loans ADD COLUMN balance_gross INT;

UPDATE loans
SET balance_gross = CAST(balancegross AS INT);

-- Convert 'ChgOffPrinGr' into integer after removing unwanted characters
UPDATE loans
SET ChgOffPrinGr = REPLACE(REPLACE(ChgOffPrinGr, '.00', ''), ',', '');

ALTER TABLE loans ADD COLUMN chgoff_prin_gr INT;

UPDATE loans
SET chgoff_prin_gr = CAST(ChgOffPrinGr AS INT);

-- Convert 'GrAppv' into integer
UPDATE loans
SET GrAppv = REPLACE(REPLACE(GrAppv, '.00', ''), ',', '');

ALTER TABLE loans ADD COLUMN gr_appv INT;

UPDATE loans
SET gr_appv = CAST(GrAppv AS INT);

-- Convert 'SBA_Appv' into integer
UPDATE loans
SET SBA_Appv = REPLACE(REPLACE(SBA_Appv, '.00', ''), ',', '');

ALTER TABLE loans ADD COLUMN sba_appv1 INT;

UPDATE loans
SET sba_appv1 = CAST(SBA_Appv AS INT);

-- Delete old columns
ALTER TABLE loans
DROP COLUMN SBA_Appv,
DROP COLUMN GrAppv,
DROP COLUMN ChgOffPrinGr,
DROP COLUMN balancegross,
DROP COLUMN disbursementgross;

-- Convert 'loannr_chkdgt' into bigint
UPDATE loans
SET loannr_chkdgt = REPLACE(REPLACE(loannr_chkdgt, '.00', ''), ',', '');

ALTER TABLE loans ADD COLUMN loannr_chkdgt1 BIGINT;

UPDATE loans
SET loannr_chkdgt1 = CAST(loannr_chkdgt AS BIGINT);

-- Drop old 'loannr_chkdgt' column
ALTER TABLE loans DROP COLUMN loannr_chkdgt;

-- Check duplicates in 'loan account number'
SELECT loannr_chkdgt1, COUNT(*)
FROM loans
GROUP BY loannr_chkdgt1
HAVING COUNT(*) > 1;

-- Remove records with NULL values in key columns
DELETE FROM loans WHERE name IS NULL;
DELETE FROM loans WHERE city IS NULL;
DELETE FROM loans WHERE Bank IS NULL;
DELETE FROM loans WHERE state IS NULL;
DELETE FROM loans WHERE bankstate IS NULL;

-- Convert 'approvalfy' into integer and drop old column
ALTER TABLE loans ADD COLUMN approvalfy1 INT;

UPDATE loans
SET approvalfy1 = CAST(approvalfy AS INT);

ALTER TABLE loans DROP COLUMN approvalfy;

-- Drop additional unwanted columns
ALTER TABLE loans DROP COLUMN state, DROP COLUMN franchisecode, DROP COLUMN chgoffdate, DROP COLUMN newexist;

-- Calculate loan metrics
SELECT
    AVG(Term) AS avg_loan_term,
    AVG(NoEmp) AS avg_number_of_employees,
    AVG(CreateJob) AS avg_jobs_created,
    AVG(RetainedJob) AS avg_jobs_retained,
    SUM(CASE WHEN RevLineCr = 'Y' THEN 1 ELSE 0 END) AS num_revolving_credit,
    SUM(CASE WHEN LowDoc = 'Y' THEN 1 ELSE 0 END) AS num_low_doc_loans,
    COUNT(*) AS total_loans,
    SUM(CASE WHEN MIS_Status = 'CHGOFF' THEN 1 ELSE 0 END) AS num_approved_loans,
    SUM(CASE WHEN MIS_Status = 'PIF' THEN 1 ELSE 0 END) AS num_disapproved_loans
FROM loans;

-- Debt-to-Income Ratio (DTI)
SELECT COALESCE((SUM(chgoff_prin_gr) + SUM(balance_gross)) / NULLIF(SUM(disbursement_gross), 0), 0) AS DTI
FROM loans;

-- Top 5 customers based on bank balance who have not defaulted in the last 3 years
SELECT *
FROM (
    SELECT name, city, balance_gross, MIS_Status, chgoff_prin_gr, approvalfy1,
           ROW_NUMBER() OVER (ORDER BY balance_gross DESC) AS rank
    FROM loans
    WHERE DisbursementDate >= CURRENT_DATE - INTERVAL '3 years'
) AS subquery
WHERE rank <= 5 AND chgoff_prin_gr = 0;

-- High-value loan amounts analysis
SELECT name, gr_appv, MIS_Status
FROM loans
WHERE gr_appv >= 5000000
ORDER BY gr_appv DESC;

-- Urban vs rural loan default rates
SELECT UrbanRural,
       100.0 * COUNT(CASE WHEN MIS_Status = 'PIF' THEN 0 END) / COUNT(*) AS percentage_paid,
       100.0 * COUNT(CASE WHEN MIS_Status = 'CHGOFF' THEN 1 END) / COUNT(*) AS percentage_defaulted
FROM loans
GROUP BY UrbanRural;

-- Loan status based on various credit score metrics
WITH cte AS (
    SELECT loannr_chkdgt1, MIS_Status, gr_appv, term, NoEmp, disbursement_gross, chgoff_prin_gr,
           CASE
               WHEN gr_appv >= 50000 AND gr_appv <= 250000 AND term <= 84 AND NoEmp <= 50
                    AND disbursement_gross <= 250000 AND chgoff_prin_gr <= 10000 THEN 'Approved'
               ELSE 'Declined'
           END AS Loan_Status
    FROM loans
)
SELECT Loan_Status, COUNT(*) AS Loan_Count
FROM cte
GROUP BY Loan_Status;

-- Average loan amount approved by fiscal year
SELECT approvalfy1, AVG(gr_appv) AS avg_loan_amount,
       AVG(gr_appv) AS overall_avg_loan_amount
FROM loans
WHERE approvalfy1 IS NOT NULL
GROUP BY approvalfy1
ORDER BY approvalfy1 DESC;

-- Top defaulters
WITH cte AS (
    SELECT name, MIS_Status, gr_appv, term, NoEmp, disbursement_gross, chgoff_prin_gr, approvalfy1,
           ROW_NUMBER() OVER (PARTITION BY MIS_Status ORDER BY gr_appv DESC) AS rn
    FROM loans
)
SELECT name, MIS_Status, gr_appv, term, NoEmp, disbursement_gross, chgoff_prin_gr, approvalfy1
FROM cte
WHERE rn <= 10
ORDER BY gr_appv DESC;

-- Optimal loan terms
SELECT term, COUNT(*) AS total_loans,
       COUNT(CASE WHEN MIS_Status = 'PIF' THEN 1 END) AS paid_in_full,
       COUNT(CASE WHEN MIS_Status = 'CHGOFF' THEN 1 END) AS charged_off,
       COUNT(CASE WHEN MIS_Status = 'PIF' OR MIS_Status = 'CHGOFF' THEN 1 END) * 100.0 / COUNT(*) AS approval_rate
FROM loans
GROUP BY term
ORDER BY approval_rate DESC;

-- Top industries by loan amount
SELECT NAICS, SUM(gr_appv) AS total_loan_amount
FROM loans
GROUP BY NAICS
ORDER BY total_loan_amount DESC
LIMIT 7;
