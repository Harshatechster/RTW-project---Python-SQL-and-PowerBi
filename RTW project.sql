-- PART 1: ALTERING THE IMPORTED TABLE --
#adding PK to parent table - claims, changing data type
USE rtw;
ALTER TABLE claims
MODIFY claim_id VARCHAR (20),
MODIFY injury_date DATE,
MODIFY gender VARCHAR (10),
MODIFY employer_id VARCHAR(20);

ALTER TABLE claims
ADD PRIMARY KEY(claim_id);

#adding FK to child tables -return_to_work, changing data type
ALTER TABLE return_to_work
MODIFY claim_id VARCHAR(20),
MODIFY days_off_work INT,
MODIFY rtw_status VARCHAR(20),
MODIFY company_name VARCHAR(50),
MODIFY job_role VARCHAR(100) ;

ALTER TABLE return_to_work
ADD constraint fk_rtw_claim
FOREIGN KEY (claim_id)
REFERENCES claims(claim_id);

#adding FK to child table - billing,changing data type
ALTER TABLE billing
MODIFY claim_id VARCHAR(20),
MODIFY invoice_amount DECIMAL (12,2), 
MODIFY paid_status VARCHAR(20),
MODIFY days_to_pay INT, 
MODIFY policy_name VARCHAR (100);

ALTER TABLE billing
ADD constraint fk_billing_claim
FOREIGN KEY (claim_id)
REFERENCES claims(claim_id);

#adding FK to child table - comp,changing data type
ALTER TABLE comp
MODIFY claim_id VARCHAR(20),
MODIFY total_income_support_paid DECIMAL (12,2),
MODIFY impairment_percentage DECIMAL (5,2),
MODIFY medical_expenses DECIMAL (12,2), 
MODIFY legal_costs DECIMAL (12,2),
MODIFY return_to_work_costs DECIMAL (12,2);

ALTER TABLE comp
ADD constraint fk_comp_claim
FOREIGN KEY (claim_id)
REFERENCES claims(claim_id);

#adding FK to child table - services, changing data type
ALTER TABLE services
MODIFY claim_id VARCHAR(20),
MODIFY service_category VARCHAR(50), 
MODIFY service_name VARCHAR(100),
MODIFY provider VARCHAR(100),
MODIFY service_cost DECIMAL(12,2);

ALTER TABLE services
ADD constraint fk_services_claim
FOREIGN KEY (claim_id)
REFERENCES claims(claim_id);

-- PART 2: CHECKING THE DATA IMPORTED --
-- check for orphans across all child tables(i.e.ghost claim check) --
SELECT 
    'billing' AS source_table, b.claim_id
FROM
    billing b
        LEFT JOIN
    claims c ON b.claim_id = c.claim_id
WHERE
    c.claim_id IS NULL 
UNION ALL SELECT 
    'services', s.claim_id
FROM
    services s
        LEFT JOIN
    claims c ON c.claim_id = s.claim_id
WHERE
    c.claim_id IS NULL;

-- finding negative or extreme outliers --
SELECT 
    claim_id,
    total_income_support_paid,
    medical_expenses,
    legal_costs,
    return_to_work_costs
FROM
    comp
WHERE
    total_income_support_paid < 0
        OR medical_expenses < 0
        OR legal_costs < 0
        OR return_to_work_costs < 0;

SELECT 
    b.claim_id, b.invoice_amount, s.service_cost
FROM
    billing b
	LEFT JOIN
    services s ON b.claim_id = s.claim_id
WHERE
    b.invoice_amount < 0
        OR s.service_cost < 0;
        
-- Finding dates that dont make sense --
SELECT c.claim_id, c.injury_date, r.days_off_work
FROM claims c
LEFT JOIN return_to_work r
ON c.claim_id = r.claim_id
WHERE r.days_off_work < 0;

-- FINDING claims with zero recorded costs --
SELECT v.claim_id, v.total_claim_cost
FROM view_total_claim_costs v -- this refers to the view created lated in this file --
WHERE v.total_claim_cost = 0;

-- Executive summary --
CREATE VIEW view_excutive_summary AS 
SELECT c.claim_id, c.injury_type, c.worker_age,
	   v.total_claim_cost, 
       r.rtw_status, r.days_off_work
FROM claims c
LEFT JOIN view_total_claim_costs v 
ON c.claim_id = v.claim_id
LEFT JOIN return_to_work r 
ON c.claim_id = r.claim_id;

-- PART 3:QUERYING THE DATABASE --

-- Total volume of claims and costs ((Big Picture)--
#1) What is the total number of claims and the average cost per claim?
SELECT 
    COUNT(DISTINCT c.claim_id) AS total_claims,
    ROUND(AVG(cc.total_income_support_paid + cc.impairment_percentage + cc.medical_expenses + cc.legal_costs + cc.return_to_work_costs),
            2) AS avg_claim_cost
FROM
    claims c
        JOIN
    comp cc ON c.claim_id = cc.claim_id;

#2) What is the total number of injuries recorded by year?
SELECT 
    YEAR(injury_date) AS injury_year, COUNT(*) AS total_claims
FROM
    claims
GROUP BY injury_year
ORDER BY injury_year;

-- Demographics--
#3) What is the age distribution of claimants and how do their associated costs compare?
SELECT 
    CASE
        WHEN c.worker_age BETWEEN 17 AND 29 THEN '17-29'
        WHEN c.worker_age BETWEEN 30 AND 50 THEN '30-50'
        ELSE '50+'
    END AS age_group,
    ROUND(AVG(cc.total_income_support_paid + cc.legal_costs + cc.medical_expenses + cc.return_to_work_costs),
            2) AS avg_claim_cost
FROM
    claims c
        JOIN
    comp cc ON c.claim_id = cc.claim_id
GROUP BY age_group
ORDER BY age_group;
 
 -- Clinical outcomes--
#4) What are the average days off work broken down by injury type?
SELECT 
    c.injury_type,
    ROUND(AVG(r.days_off_work), 2) AS avg_days_off
FROM
    claims c
        LEFT JOIN
    return_to_work r ON c.claim_id = r.claim_id
GROUP BY c.injury_type
ORDER BY avg_days_off DESC;

#5) What is the "Full Return to Work" rate for each injury type?
SELECT 
    c.injury_type,
    CONCAT(ROUND(SUM(CASE
                        WHEN r.rtw_status = 'Full' THEN 1
                        ELSE 0
                    END) / COUNT(*) * 100,
                    2),
            '%') AS full_rtw_rate
FROM
    claims c
        JOIN
    return_to_work r ON c.claim_id = r.claim_id
GROUP BY c.injury_type;

#6) Which job roles and companies experience the highest average days off work?
SELECT 
    company_name,
    job_role,
    ROUND(AVG(days_off_work), 1) AS avg_days_off
FROM
    return_to_work
GROUP BY job_role
ORDER BY company_name ASC;

#7) What is the overall percentage distribution of Return to Work (RTW) statuses?
SELECT rtw_status, COUNT(*) *100/SUM(COUNT(*)) OVER()
FROM return_to_work
GROUP BY rtw_status;

-- Financial Drivers

#8) Create a comprehensive summary view of all claim costs including service fees.
CREATE VIEW view_total_claim_costs AS 
WITH agg_services AS (
SELECT 
claim_id, 
SUM(service_cost) as total_service_cost
FROM services
GROUP BY claim_id 
) 
SELECT
c.claim_id, 
COALESCE(c.total_income_support_paid,0)  AS income_support, 
COALESCE(c.medical_expenses,0) AS medical_expense, 
COALESCE(c.legal_costs, 0) AS legal_cost,
COALESCE(c.return_to_work_costs,0) AS return_to_work_cost,
COALESCE(s.total_service_cost,0) AS total_service_cost,
ROUND(
COALESCE(c.total_income_support_paid,0)
+ COALESCE(c.medical_expenses,0) 
+ COALESCE(c.legal_costs, 0) 
+ COALESCE(c.return_to_work_costs,0)
+ COALESCE(s.total_service_cost,0) 
)  AS total_claim_cost 
FROM comp c
LEFT JOIN agg_services s 
ON c.claim_id = s.claim_id;

#9) Which service providers are the biggest cost drivers?
SELECT 
    provider, SUM(service_cost) AS total_service_cost
FROM
    services
GROUP BY provider
ORDER BY total_service_cost DESC;

#10) For each claim, what is the primary cost driver (Medical, Legal, or Services)?
SELECT 
    c.claim_id,
    CASE
        WHEN
            v.medical_expense >= v.legal_cost
                AND v.medical_expense >= v.return_to_work_cost
                AND v.medical_expense >= v.total_service_cost
        THEN
            'medical driven'
        WHEN
            v.legal_cost >= v.medical_expense
                AND v.legal_cost >= v.return_to_work_cost
                AND v.legal_cost >= v.total_service_cost
        THEN
            'legal driven'
        WHEN
            v.total_service_cost >= v.medical_expense
                AND v.total_service_cost >= v.legal_cost
                AND v.total_service_cost >= v.return_to_work_cost
        THEN
            'Service Fee Driven'
        ELSE 'RTW driven'
    END AS primary_cost_driver,
    v.total_claim_cost
FROM
    claims c
        JOIN
    view_total_claim_costs v ON c.claim_id = v.claim_id
ORDER BY primary_cost_driver;

-- Operational/Billing--
#11) What is the average time taken to pay invoices per policy name?
SELECT 
    policy_name, ROUND(AVG(days_to_pay)) AS avg_days_to_pay
FROM
    billing
GROUP BY policy_name
ORDER BY avg_days_to_pay DESC;

#12) How many claims are allocated to each specific policy?
SELECT 
    policy_name, COUNT(claim_id) AS claim_id_count
FROM
    billing
GROUP BY policy_name
ORDER BY claim_id_count DESC;

#13) What is the payment status of invoices (On time, Delayed, or Severely Delayed)?
SELECT 
    claim_id,
    invoice_amount,
    days_to_pay,
    CASE
        WHEN days_to_pay <= 28 THEN 'On time'
        WHEN days_to_pay BETWEEN 28 AND 58 THEN 'Delayed'
        ELSE 'Severely Delayed'
    END AS payment_status
FROM
    billing;



