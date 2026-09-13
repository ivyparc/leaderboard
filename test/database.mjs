import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
const { PGlite } = await import(process.env.PGLITE_MODULE || '@electric-sql/pglite');
test('monthly rollover deletes scores, preserves names, rejects expired writes and isolates boards', async () => {
 const db = new PGlite();
 try {
 await db.exec('create role anon; create role authenticated; create role service_role;');
 const sql = await readFile(new URL('../react/supabase/leaderboard.sql',import.meta.url),'utf8');
 await db.exec(sql); await db.exec(sql);
 const period = (await db.query("select leaderboard_period('test','default') as p")).rows[0].p;
 const generated = (await db.query("select leaderboard_name('test','default',md5('new')::uuid) as n")).rows[0].n;
 assert.match(generated,/^[A-Z][a-z]+[A-Z][a-z]+\d{2}$/);
 await assert.rejects(db.query("insert into app_leaderboard_names values('test','default',md5('collision')::uuid,$1)",[generated.toLowerCase()]));
 await db.query("insert into app_leaderboard_scores values('test','default',md5('new')::uuid,$1,$2,null,119,now())",[period,generated]);
 // Simulate persisted rows from before a boundary without changing the clock.
 await db.exec("alter table app_leaderboard_scores disable trigger user; update app_leaderboard_scores set period='2020-01'; alter table app_leaderboard_scores enable trigger user;");
 assert.equal((await db.query("select leaderboard_period('test','default') as p")).rows[0].p,period);
 assert.equal((await db.query('select count(*)::int as n from app_leaderboard_scores')).rows[0].n,0);
 assert.equal((await db.query("select leaderboard_name('test','default',md5('new')::uuid) as n")).rows[0].n,generated);
 await assert.rejects(db.exec("insert into app_leaderboard_scores values('test','default',md5('stale')::uuid,'2020-01','Stale',null,119,now())"));
 await db.query("insert into app_leaderboard_scores values('test','default',md5('new')::uuid,$1,$2,null,175,now())",[period,generated]);
 assert.equal((await db.query('select score from app_leaderboard_scores')).rows[0].score,175);
 await db.query("insert into app_leaderboard_scores values('other','default',md5('other')::uuid,$1,'Other',null,120,now())",[period]);
 await db.exec("alter table app_leaderboard_scores disable trigger user; update app_leaderboard_scores set period='2020-01' where app_id='test'; alter table app_leaderboard_scores enable trigger user;");
 await db.exec('select leaderboard_purge_expired()');
 assert.deepEqual((await db.query('select app_id from app_leaderboard_scores')).rows,[{app_id:'other'}]);
 } finally { await db.close(); }
});
