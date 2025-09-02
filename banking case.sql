#explore the data
DESCRIBE mydb.users;
DESCRIBE mydb.cards;
DESCRIBE mydb.transactions;
Select * from  mydb.users
LIMIT 3;
Select * from  mydb.cards
LIMIT 3;
Select * from mydb.transactions
LIMIT 3;



#cleaning the data
# turn aout empty string to null, then delete the decimal point and turn it into int
UPDATE mydb.transactions
SET zip = NULL
WHERE zip = '';
UPDATE mydb.transactions
SET zip = REPLACE(zip, '.0', '');
ALTER TABLE mydb.transactions
MODIFY COLUMN zip  INT;
# delete the dollar icon
UPDATE mydb.users
SET 
yearly_income = REPLACE(yearly_income, '$', ''),
per_capita_income = REPLACE(per_capita_income, '$', ''),
total_debt = REPLACE(total_debt, '$', '');
ALTER TABLE mydb.users
MODIFY COLUMN yearly_income INT,
MODIFY COLUMN per_capita_income INT,
MODIFY COLUMN total_debt INT;
# turn text to date
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
SET 
birth_year = STR_TO_DATE(CONCAT('01/01/', birth_year), '%d/%m/%Y');
ALTER TABLE mydb.users 
MODIFY COLUMN birth_year DATE; 



#load for transactions (spending) analysis (users, cards, transactions)
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
t.`date` as trx_date,
t.amount as trx_amount,
t.use_chip,
t.mcc,
t.merchant_id,
t.merchant_city,
t.merchant_state
FROM mydb.users u
LEFT JOIN mydb.cards c
ON u.id = c.client_id
LEFT JOIN mydb.transactions t
ON u.id = t.client_id;



#load for fraud analysis (cards and transactions)
#searching for cards which have transaction but also recorded exist on the dark web
SELECT
c.id AS card_id,
t.id AS trx_id,
c.card_on_dark_web,
t.amount
FROM mydb.cards c
LEFT JOIN mydb.transactions t
ON c.id = t.card_id
WHERE c.card_on_dark_web = "YES"
ORDER BY c.id ;
#No card data available on the dark web; fraud detection can instead focus on suspicious transactions:
#For example: high-value transactions at unusual hours, or two distant locations within minutes.

#tracking transactions that are 5 times higher than the normal average transactions in unusual time per user
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

#Tracking suspicious transactions made by the same card in different merchant states on the same day
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

#Tracking suspicious transactions made by the same card in different merchant states within 30 minutes
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


























