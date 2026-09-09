// Run with: PGLITE_MODULE=/absolute/path/to/pglite/dist/index.js node --test test/database.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
const { PGlite } = await import(process.env.PGLITE_MODULE || '@electric-sql/pglite');
test('unique names, persistent periods, threshold and rollover', async () => {
 const db = new PGlite();
 try {
 await db.exec('create role anon; create role authenticated; create role service_role;');
 const sql = await readFile(new URL('../react/supabase/leaderboard.sql',import.meta.url),'utf8');
 await db.exec(sql);
 await db.exec(sql); // Migration is rerunnable.
 const period = async () => (await db.query("select leaderboard_period('test','default') as p")).rows[0].p;
 await period();
 await db.exec("update app_leaderboard_boards set period='2020-01'");
 assert.equal(await period(),'2020-01');
 await db.exec(`insert into app_leaderboard_scores(app_id,scope,player_id,period,name,score)
 select 'test','default',md5(n::text)::uuid,'2020-01','Existing'||n,0 from generate_series(1,1000) n`);
 assert.equal((await db.query('select reset_at from app_leaderboard_boards')).rows[0].reset_at,null);
 assert.equal(await period(),'2020-01');
 await db.exec("insert into app_leaderboard_scores values('test','default',md5('1001')::uuid,'2020-01','Existing1001',null,0,now())");
 assert.ok((await db.query('select reset_at from app_leaderboard_boards')).rows[0].reset_at);
 assert.equal(await period(),'2020-01');
 await db.exec("update app_leaderboard_scores set score=10 where name='Existing1001'");
 const generated = (await db.query("select leaderboard_name('test','default',md5('new')::uuid) as n")).rows[0].n;
 assert.match(generated,/^[A-Z][a-z]+[A-Z][a-z]+\d{2}$/);
 assert.equal((await db.query("select leaderboard_name('test','default',md5('new')::uuid) as n")).rows[0].n,generated);
 await assert.rejects(db.query("insert into app_leaderboard_names values('test','default',md5('collision')::uuid,$1)",[generated.toLowerCase()]));
 await db.exec("update app_leaderboard_boards set reset_at=now()-interval '1 second'");
 assert.notEqual(await period(),'2020-01');
 assert.equal((await db.query('select count(*)::int as n from app_leaderboard_scores')).rows[0].n,1001);
 assert.equal((await db.query("select leaderboard_name('test','default',md5('new')::uuid) as n")).rows[0].n,generated);
 await assert.rejects(db.exec("insert into app_leaderboard_scores values('test','default',md5('stale')::uuid,'2020-01','Stale',null,0,now())"));
 assert.equal((await db.query("select leaderboard_period('test','another') as p")).rows.length,1);
 } finally { await db.close(); }
});
