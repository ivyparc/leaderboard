import test from 'node:test';
import assert from 'node:assert/strict';
import { createLeaderboardClient } from '../src/leaderboardClient.js';

test('client uses reserved names and persistent server period for writes and reads', async () => {
 const calls=[];
 const values=new Map();
 const client=createLeaderboardClient({namespace:'test',supabaseUrl:'https://example.test',supabaseAnonKey:'test',storage:{getItem:k=>values.get(k),setItem:(k,v)=>values.set(k,v)},fetchImpl:async(url,options)=>{
  const path=String(url);calls.push({path,options});
  if(path.endsWith('/leaderboard_period')) return new Response(JSON.stringify('2020-01'));
  if(path.endsWith('/leaderboard_name')) return new Response(JSON.stringify('AzureBison53'));
  return new Response(JSON.stringify([]));
 }});
 assert.equal(await client.getOrCreatePlayerName(),'AzureBison53');
 await client.submitScore(50, {completedAt:'2020-01-02T00:00:00Z'});
 const write=calls.find(c=>c.options.method==='POST'&&c.path.includes('on_conflict'));
 assert.equal(JSON.parse(write.options.body).period,'2020-01');
 assert.equal(JSON.parse(write.options.body).name,'AzureBison53');
 await client.fetchSnapshot();
 assert.ok(calls.some(c=>new URL(c.path).searchParams.get('period')==='eq.2020-01'));
});

test('legacy endpoint must explicitly implement reservation instead of fake success', async()=>{
 const client=createLeaderboardClient({namespace:'test',endpoint:'https://example.test',storage:{getItem:()=> 'saved-id',setItem:()=>{}},fetchImpl:async()=>new Response('{}')});
 await assert.rejects(client.getOrCreatePlayerName(),/must implement/);
});

for (const scoreOrder of ['lower', 'higher']) {
 test(`reset requires gameplay and keeps Previous private (${scoreOrder})`, async () => {
  let period='2026-08', score=null;
  const values=new Map(), writes=[];
  const client=createLeaderboardClient({namespace:'monthly', scoreOrder, supabaseUrl:'https://example.test',supabaseAnonKey:'test', storage:{getItem:k=>values.get(k),setItem:(k,v)=>values.set(k,v)},fetchImpl:async(url,options)=>{
   const path=String(url);
   if(path.endsWith('/leaderboard_period')) return Response.json(period);
   if(path.endsWith('/leaderboard_name')) return Response.json('AzureBison53');
   if(options.method==='POST') {const body=JSON.parse(options.body); writes.push(body);score=body.score;return new Response(null,{status:204});}
   const select=new URL(url).searchParams.get('select');
   return Response.json(score===null?[]:select==='score'?[{score}]:[{player_id:client.getOrCreatePlayerId(),name:'AzureBison53',score}]);
  }});
  await client.submitScore(119, {completedAt:`${period}-02T00:00:00Z`});
  await client.fetchSnapshot();
  period='2026-09';score=null;
  await assert.rejects(client.submitScore(50, {completedAt:'2026-08-31T23:59:59Z'}), /expired/);
  await client.activateCurrentPeriod();
  const empty=await client.fetchSnapshot();
  assert.equal(writes.length,1);assert.equal(empty.currentPlayer,null);assert.deepEqual(empty.entries,[]);assert.equal(empty.previousScore,119);
  const worse=scoreOrder==='lower'?175:100;
  await client.submitScore(worse, {completedAt:`${period}-02T00:00:00Z`});
  const slower=await client.fetchSnapshot();
  assert.equal(slower.currentPlayer.score,worse);assert.equal(slower.previousScore,119);assert.equal(slower.showPrevious,true);
  await client.submitScore(119, {completedAt:`${period}-02T00:00:00Z`});
  assert.equal((await client.fetchSnapshot()).showPrevious,false);
  await client.submitScore(scoreOrder==='lower'?110:130, {completedAt:`${period}-02T00:00:00Z`});
  assert.equal((await client.fetchSnapshot()).showPrevious,false);
  assert.ok(writes.every(w=>!('previousScore' in w)));
 });
}
