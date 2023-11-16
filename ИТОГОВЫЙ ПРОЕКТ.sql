--============= ИТОГОВЫЙ ПРОЕКТ ПО МОДУЛЮ «SQL И ПОЛУЧЕНИЕ ДАННЫХ» =================

--Задание 1. Выведите названия самолётов, которые имеют менее 50 посадочных мест.

select a.model
from aircrafts a 
join seats s on s.aircraft_code = a.aircraft_code 
group by a.aircraft_code 
having count(s.seat_no) < 50


--Задание 2. Выведите процентное изменение ежемесячной суммы бронирования билетов, округленной до сотых.

select date_trunc as "Месяц", sum as "Сумма бронирования",
case 
	when sum >= lag then round((sum / lag - 1) * 100, 2)
	else - round((1- sum / lag) * 100, 2)
end as "Процентное изменение"
from (
	select 
		date_trunc('month', book_date)::date, 
		sum(total_amount),
		lag(sum(total_amount)) over (order by date_trunc('month', book_date)::date)
	from bookings b 
	group by date_trunc('month', book_date)::date
) t

--Задание 3. Выведите названия самолётов без бизнес-класса. Используйте в решении функцию array_agg

select a.model
from (
	select aircraft_code, array_agg(fare_conditions)
	from seats s 
	group by aircraft_code
) t 
join aircrafts a on a.aircraft_code = t.aircraft_code
where array_position(array_agg, 'Business') is null

/*
Задание 4. 
Выведите накопительный итог количества мест в самолётах по каждому аэропорту на каждый день. 
Учтите только те самолеты, которые летали пустыми и только те дни, 
когда из одного аэропорта вылетело более одного такого самолёта.
Выведите в результат код аэропорта, дату вылета, количество пустых мест и накопительный итог.
 */

with empty_flights as ( --пустые полеты и их количество за день
	select  departure_airport, f.flight_id, aircraft_code, actual_departure,
	count(f.flight_id) over (partition by departure_airport, actual_departure::date) -- выводим количество таких полетов за день
	from flights f 
	left join ticket_flights tf on tf.flight_id = f.flight_id 
	left join boarding_passes bp on bp.flight_id = tf.flight_id
	where bp.flight_id is null and f.actual_departure is not null
)
select distinct departure_airport as "Код аэропорта", actual_departure as "Дата вылета", 
count(s.seat_no) over (partition by departure_airport, actual_departure) as "Количество пустых мест",
count(s.seat_no) over (partition by departure_airport, actual_departure :: date order by actual_departure) as "Накопительный итог"
from empty_flights ef
join seats s on s.aircraft_code = ef.aircraft_code
where count > 1 -- отсекаем полеты которые были единственными за день
order by departure_airport, actual_departure
	
/*
Задание 5. 
Найдите процентное соотношение перелётов по маршрутам от общего количества перелётов. 
Выведите в результат названия аэропортов и процентное отношение.
Используйте в решении оконную функцию.
 */

select distinct a1.airport_name as "Аэропорт отправления", a2.airport_name as "Аэропорт прибытия", 
round(((count(flight_id) over (partition by a1.airport_code, a2.airport_code)::numeric 
/ count(flight_id) over ()::numeric) * 100), 3) as "Процентное отношение от общего количества перелётов"
from flights f 
left join airports a1 on a1.airport_code = f.departure_airport 
left join airports a2 on a2.airport_code = f.arrival_airport

/*
 Задание 6.
 Выведите количество пассажиров по каждому коду сотового оператора. 
 Код оператора – это три символа после +7
 */

select substring(contact_data ->> 'phone', 3, 3) as "Код оператора", 
count(distinct passenger_id) as "Количество пассажиров"
from tickets t 
group by substring(contact_data ->> 'phone', 3, 3)

/*
Задание 7.
Классифицируйте финансовые обороты (сумму стоимости перелетов) по маршрутам:
до 50 млн – low
от 50 млн включительно до 150 млн – middle
от 150 млн включительно – high
Выведите в результат количество маршрутов в каждом полученном классе.
*/

--запрос выводит классы в порядке low, middle, high
--explain analyze --70097.85/706
with cte1 as (
	select departure_airport, arrival_airport, sum(tf.amount),
	case when sum(tf.amount) < '50000000' then array['1', 'low']
	when sum(tf.amount) >= '150000000' then array['3', 'high']
	else array['2', 'middle']
	end as "class"
	from flights f 
	left join ticket_flights tf on tf.flight_id = f.flight_id 
	group by departure_airport, arrival_airport
)
select class[2], count(*)
from cte1
group by class
order by class[1]

--запрос выводит классы неупорядоченно
--explain analyze --70089.70 / 696.
with cte1 as (
	select departure_airport, arrival_airport as "route", 
	case when sum(tf.amount) < '50000000' then 'low'
	when sum(tf.amount) >= '150000000' then 'high'
	else 'middle'
	end as "class"
	from flights f 
	left join ticket_flights tf on tf.flight_id = f.flight_id 
	group by departure_airport, arrival_airport
)
select class, count(*)
from cte1
group by class

/*
 Задание 8.
 Вычислите медиану стоимости перелетов, медиану стоимости бронирования и
 отношение медианы бронирования к медиане стоимости перелетов, результат округлите до сотых. 
 */

select median1 as "Медиана стоимости перелетов", 
median2 as "Медиана стоимости бронирования", 
round((median2/median1)::numeric, 2) as "Отношение"
from (
	select 1 as "num", 
	percentile_cont(0.5) within group (order by amount) as "median1" 
	from ticket_flights
) t1
join (
	select 1 as "num", 
	percentile_cont(0.5) within group (order by total_amount) as "median2" 
	from bookings
) t2 on t2.num = t1.num

/*
Задание 9.
Найдите значение минимальной стоимости одного километра полёта для пассажира. 
Для этого определите расстояние между аэропортами и учтите стоимость перелета.

Для поиска расстояния между двумя точками на поверхности Земли используйте дополнительный модуль earthdistance. 
Для работы данного модуля нужно установить ещё один модуль – cube.

Важно: 
Установка дополнительных модулей происходит через оператор CREATE EXTENSION название_модуля.
В облачной базе данных модули уже установлены.
Функция earth_distance возвращает результат в метрах.

 */

create extension earthdistance with cascade 

select distinct a1.airport_name as "departure_airport", a2.airport_name as "arrival_airport", 
	earth_distance(ll_to_earth(a1.latitude, a1.longitude), ll_to_earth(a2.latitude, a2.longitude)) / 1000 as "distance_in_km",
	min(tf.amount) as "min_cost", 
	min(tf.amount) / (earth_distance(ll_to_earth(a1.latitude, a1.longitude), ll_to_earth(a2.latitude, a2.longitude)) / 1000) as "min_cost_per_km"
from flights f 
	left join airports a1 on a1.airport_code = departure_airport
	left join airports a2 on a2.airport_code = arrival_airport
	left join ticket_flights tf on tf.flight_id = f.flight_id
group by a1.airport_code, a2.airport_code, a1.latitude, a1.longitude, a2.latitude, a2.longitude
order by min_cost_per_km 
limit 1 

