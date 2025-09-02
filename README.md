Banking Case 

In this case, three public banking datasets are used: users, cards, and transactions. A banking company wants to analyze customer spending behavior to improve its business programs. Additionally, the company aims to conduct a fraud investigation. Although there is no clear evidence of fraud, some suspicious data patterns have been detected, creating the need for a dashboard to monitor both customer spending and potential fraud symptoms.

Analytics Results:
1. In 7 days, average transaction value is $160.15, with on average almost 11 transaction per user. In detail, each user has around 3 transactions per day.
2. The majority of users are categorized in low-income people with annual income under $40,000.  This group accounted for the largest share of transactions and transaction amounts. However, this group has a small average value per transactions compared to other groups.
3. From mcc data,  groceries & supermarkets, foods, and service stations was the top categories by number of transactions. These was top three for the majority of users except the high-income people which had toll & fees and  wire transfers & money orders as their top categories.
4. The detailed transactions table shows that most of users with high credit scores and transactions volume was from lower middle-income groups and carry a high level of debt.
5. The tables show suspicious transactions. The first one is used for monitoring high-value transactions at unusual hours. For example: At the first row, we can suspect user 171 for made a transaction which value almost 21 times his average transaction value at 3 am.
6. The second table shows suspicious transactions in 2 distant locations within minutes. For example: user 1827 made 2 different transactions in NV and CA (271 miles, taking around 4 hours and 21 minutes to drive) just in 2 minutes.

Actionable insights:
1. Prioritize offers to get younger users, who are more productive and have higher consumption levels.
2. Due to a high share of consumptive transactions trend (high transactions but small average value for daily needs) by lower-middle people who carry a notable amount of debt, the company cost and risks of credit failure could potentially increase over time. The company should consider the debt history of the user before issuing a credit card and approving the credit limit.
3. The company should make fraud prediction models based on suspicious transactions and give users warnings right after the suspicious transactions happen.

SIMPLE LOOKER DASHBOARD: https://lookerstudio.google.com/s/gHVykxFuZc0

SQL SCRIPTS:

1. Data Exploration
```
DESCRIBE mydb.users;
DESCRIBE mydb.cards;
DESCRIBE mydb.transactions;

SELECT * FROM mydb.users LIMIT 3;
SELECT * FROM mydb.cards LIMIT 3;
SELECT * FROM mydb.transactions LIMIT 3;
```
2. Data Cleaning

2.1 Cleaning ZIP codes
Convert empty strings to NULL, remove decimal points, and change column type to integer:
```
UPDATE mydb.transactions
SET zip = NULL
WHERE zip = '';

UPDATE mydb.transactions
SET zip = REPLACE(zip, '.0', '');

ALTER TABLE mydb.transactions
MODIFY COLUMN zip INT;
```
2.2 Removing currency symbols & converting to integers
```
UPDATE mydb.users
SET 
    yearly_income = REPLACE(yearly_income, '$', ''),
    per_capita_income = REPLACE(per_capita_income, '$', ''),
    total_debt = REPLACE(total_debt, '$', '');

ALTER TABLE mydb.users
MODIFY COLUMN yearly_income INT,
MODIFY COLUMN per_capita_income INT,
MODIFY COLUMN total_debt INT;
```
2.3 Converting text dates to MySQL `DATE` format
```
UPDATE mydb.cards
SET 
    expires = STR_TO_DATE(CONCAT('01/', expires), '%d/%m/%Y'),
    acct_open_date = STR_TO_DATE(CONCAT('01/', acct_open_date), '%d/%m/%Y'),
    year_pin_last_changed = STR_TO_DATE(CONCAT('01/01/', year_pin_last_changed), '%d/%m/%Y');

ALTER TABLE mydb.cards 
MODIFY COLUMN expires DATE,
MODIFY COLUMN acct_open_date DATE,
MODIFY COLUMN year_pin_last_changed DATE;

UPDATE mydb.users
SET birth_year = STR_TO_DATE(CONCAT('01/01/', birth_year), '%d/%m/%Y');

ALTER TABLE mydb.users 
MODIFY COLUMN birth_year DATE;
```
3. Transaction Analysis

Join users, cards, and transactions to analyze spending patterns:
```
SELECT
    u.id AS user_id,
    u.current_age,
    u.gender,
    u.per_capita_income,
    u.yearly_income,
    u.total_debt,
    u.credit_score,
    u.num_credit_cards,
    c.id AS card_id,
    c.card_brand,
    c.card_type,
    c.credit_limit,
    c.acct_open_date,
    c.expires,
    TIMESTAMPDIFF(YEAR, u.birth_year, c.acct_open_date) AS age_at_open,
    t.id AS trx_id,
    t.`date` AS trx_date,
    t.amount AS trx_amount,
    t.use_chip,
    t.mcc,
    t.merchant_id,
    t.merchant_city,
    t.merchant_state
FROM mydb.users u
LEFT JOIN mydb.cards c ON u.id = c.client_id
LEFT JOIN mydb.transactions t ON u.id = t.client_id;
```
4. Fraud Analysis
4.1 Cards found on the dark web
```
  SELECT
    c.id AS card_id,
    t.id AS trx_id,
    c.card_on_dark_web,
    t.amount
FROM mydb.cards c
LEFT JOIN mydb.transactions t ON c.id = t.card_id
WHERE c.card_on_dark_web = "YES"
ORDER BY c.id;
```
-- No card data was available on the dark web. Fraud detection instead focuses on suspicious transaction patterns.
4.2 High-value transactions at unusual hours
Find transactions more than 5× the user’s average, between midnight and 5 AM:
```
WITH user_avg AS (
    SELECT 
        client_id,
        AVG(amount) AS avg_amount
    FROM mydb.transactions
    GROUP BY client_id
)
SELECT 
    t.client_id as user_id,
    t.id as trx_id,
    t.`date` as trx_date,
    t.amount,
    t.merchant_id,
    t.merchant_city,
    t.merchant_state,
    u.avg_amount,
    ROUND(t.amount / u.avg_amount, 3) AS times_above_avg
FROM mydb.transactions t
JOIN user_avg u 
    ON t.client_id = u.client_id
WHERE 
    t.amount > u.avg_amount * 5  -- "very high" means > 5x average
    AND HOUR(t.`date`) BETWEEN 0 AND 5  -- unusual time: midnight to 5 AM
ORDER BY t.client_id, t.`date`;
```
4.3 Same card used by swipe transaction in different merchant states on the same day
```
WITH suspicious_cards AS (
    SELECT
        client_id,
        card_id,
        DATE(`date`) AS trx_date
    FROM mydb.transactions
    WHERE use_chip = 'swipe transaction'
    GROUP BY client_id, card_id, DATE(`date`)
    HAVING COUNT(DISTINCT merchant_state) > 1
)
SELECT
    t.id,
    t.client_id,
    t.card_id,
    `date` AS trx_date,
    t.merchant_state,
    t.use_chip,
    t.amount
FROM mydb.transactions t
JOIN suspicious_cards s
    ON t.client_id = s.client_id
    AND t.card_id = s.card_id
    AND DATE(t.`date`) = s.trx_date
WHERE t.use_chip = 'swipe transaction'
ORDER BY t.client_id, t.card_id, trx_date, t.merchant_state;
```

4.4 Same card used in different merchant states within 30 minutes
Because someone might make transactions while traveling to other states in a day, we shortened the time to 30 minutes
```
SELECT 
    t1.client_id,
    t1.card_id,
    t1.`date` AS trx_time_1,
    t1.merchant_state AS state_1,
    t1.id AS trx_id_1,
    t2.`date` AS trx_time_2,
    t2.merchant_state AS state_2,
    t2.id AS trx_id_2,
    ABS(TIMESTAMPDIFF(MINUTE, t1.`date`, t2.`date`)) AS time_difference
FROM mydb.transactions t1
JOIN mydb.transactions t2 -- self join to compare data
    ON t1.card_id = t2.card_id
    AND t1.client_id = t2.client_id
    AND t1.merchant_state <> t2.merchant_state
    AND t1.use_chip = 'swipe transaction'
    AND t2.use_chip = 'swipe transaction'
    AND ABS(TIMESTAMPDIFF(MINUTE, t1.`date`, t2.`date`)) <= 30
WHERE t1.`date` < t2.`date`
ORDER BY t1.client_id, t1.card_id, t1.`date`;
```




