'use strict';
/* Crafted-DB query oracle.  No collector or query implementation is imported. */
exports.runQueryChecks = function runQueryChecks(h) {
  const {assert, fs, path, root, queryRun, assertRefusal, twoArrays, makeDb, rows, sql, hash, temp, summaryHeaders, applicationHeaders, limitations, run} = h;
  const formats = ['box','list','json','csv','line','markdown'];
  let mutations = 0, successes = 0;
  const expectInconsistent = (db, label) => { const r = queryRun(db, ['0']); assertRefusal(r, 'INCONSISTENT_CATALOGUE'); mutations++; };
  const relaxedApplications = db => sql(db, `ALTER TABLE functor_applications RENAME TO functor_applications_checked;
    CREATE TABLE functor_applications AS SELECT * FROM functor_applications_checked;
    DROP TABLE functor_applications_checked;`);
  const width = s => [...String(s)].length, pad = (s, n) => String(s) + ' '.repeat(Math.max(0, n - width(s))), centre = (s, n) => { const d = Math.max(0, n - width(s)); return ' '.repeat(Math.floor(d / 2)) + s + ' '.repeat(Math.ceil(d / 2)); };
  const csv = s => /[,"]|[\x00-\x20\x80-\xff]/.test(String(s)) ? `"${String(s).replaceAll('"','""')}"` : String(s);
  const render = (mode, headers, values) => {
    const cells = values.map(row => headers.map(k => row[k] === null ? '' : String(row[k]))); if (!cells.length) return '';
    const ws = headers.map((h, i) => Math.max(width(h), ...cells.map(r => width(r[i]))));
    if (mode === 'json') return `[${values.map(r => JSON.stringify(Object.fromEntries(headers.map(k => [k, r[k]]))).replace(/,/g, ',')).join(',\n')}]\n`;
    if (mode === 'list') return cells.map(r => r.join('|')).join('\n') + '\n';
    if (mode === 'csv') return cells.map(r => r.map(csv).join(',')).join('\n') + '\n';
    if (mode === 'line') { const w = Math.max(...headers.map(width)); return cells.map(r => headers.map((h,i) => `${' '.repeat(w-width(h))}${h} = ${r[i]}`).join('\n')).join('\n\n') + '\n'; }
    if (mode === 'markdown') { const line = (r, align) => `| ${r.map((x,i) => align(x,ws[i])).join(' | ')} |`; return [line(headers,centre), `|${ws.map(w => '-'.repeat(w+2)).join('|')}|`, ...cells.map(r => line(r,pad))].join('\n') + '\n'; }
    const rule = (l,m,r) => l + ws.map(w => '─'.repeat(w+2)).join(m) + r;
    const line = (r, align) => `│ ${r.map((x,i) => align(x,ws[i])).join(' │ ')} │`;
    return [rule('┌','┬','┐'),line(headers,centre),rule('├','┼','┤'),...cells.map(r => line(r,pad)),rule('└','┴','┘')].join('\n') + '\n';
  };
  const oracle = (db, limit, mode) => {
    const summary = `SELECT 'v1' AS contract, r.selected_inputs AS selected_inputs,
      (SELECT count(*) FROM functor_catalogue_inputs i WHERE i.producer_run_id=r.producer_run_id AND i.outcome='collected') AS collected_inputs,
      (SELECT count(*) FROM functor_applications a WHERE a.producer_run_id=r.producer_run_id) AS total,
      MIN((SELECT count(*) FROM functor_applications a WHERE a.producer_run_id=r.producer_run_id),${limit}) AS returned,
      CASE WHEN ${limit} < (SELECT count(*) FROM functor_applications a WHERE a.producer_run_id=r.producer_run_id) THEN 1 ELSE 0 END AS truncated,
      'selected_cmt_syntax_only' AS scope, '${limitations}' AS limitations
      FROM functor_catalogue_runs r`;
    const apps = `SELECT i.artifact,i.source,i.compiler_unit,a.ordinal,a.application_kind,a.location,a.head,a.argument,a.diagnostics
      FROM functor_applications a JOIN functor_catalogue_inputs i USING(producer_run_id,artifact)
      ORDER BY i.artifact,a.ordinal LIMIT ${limit}`;
    const first = render(mode, summaryHeaders, rows(db, summary));
    const second = render(mode, applicationHeaders, rows(db, apps));
    return mode === 'json' ? first + (second || '[]\n') : first + second;
  };
  temp(dir => {
    const valid = path.join(dir, 'valid.db'); makeDb(valid); const original = hash(valid);
    for (const limit of [undefined, '0', '2']) for (const format of formats) {
      const r = queryRun(valid, limit === undefined ? [] : [limit], format);
      assert.equal(r.status, 0, `${format}/${limit}: ${r.stderr}`); assert.equal(hash(valid), original);
      assert.equal(r.stdout, oracle(valid, limit === undefined ? 50 : Number(limit), format), `byte oracle ${format}/${limit}`);
      if (format === 'json') { const [s, a] = twoArrays(r.stdout); assert.deepEqual(Object.keys(s[0]), summaryHeaders); assert(a.every(x => JSON.stringify(Object.keys(x)) === JSON.stringify(applicationHeaders))); assert.equal(s[0].limitations, limitations); assert.equal(s[0].returned, limit === '0' ? 0 : limit === '2' ? 2 : 3); }
      successes++;
    }
    const empty = path.join(dir, 'empty.db'); makeDb(empty, "DELETE FROM functor_applications; UPDATE functor_catalogue_inputs SET expected_applications=0; DELETE FROM functor_catalogue_inputs WHERE artifact='b.cmt'; UPDATE functor_catalogue_runs SET selected_inputs=1"); const before = hash(empty);
    for (const limit of ['0','2']) for (const format of formats) { const r = queryRun(empty, [limit], format); assert.equal(r.status, 0, r.stderr); assert.equal(hash(empty), before); assert.equal(r.stdout, oracle(empty, Number(limit), format), `empty byte oracle ${format}/${limit}`); if (format === 'json') { const [s, a] = twoArrays(r.stdout); assert.equal(s[0].total, 0); assert.deepEqual(a, []); } successes++; }
    for (const x of ['','+1',' 1','1 ','-1','0x10','١','999999999999999999999999999999999999']) assertRefusal(queryRun('/does/not/exist.db', [x]), 'usage|limit|integer', 2);
    assertRefusal(queryRun('/does/not/exist.db', ['1','extra']), 'usage|limit|integer', 2);
    assertRefusal(queryRun(dir, []), 'open|database|directory', 2);
    const mutationsSql = [
      "UPDATE functor_catalogue_runs SET selected_inputs=1", "UPDATE functor_catalogue_inputs SET expected_applications=9", "UPDATE functor_catalogue_inputs SET source=NULL", "UPDATE functor_catalogue_inputs SET source=X'00'", "UPDATE functor_catalogue_inputs SET compiler_unit=NULL", "UPDATE functor_catalogue_inputs SET module_id=99", "UPDATE functor_applications SET ordinal=0 WHERE artifact='a.cmt' AND ordinal=2", "UPDATE functor_applications SET ordinal=1 WHERE artifact='a.cmt' AND ordinal=2", "UPDATE functor_applications SET ordinal=1.5 WHERE artifact='a.cmt' AND ordinal=2", "UPDATE functor_applications SET location=NULL WHERE artifact='a.cmt' AND ordinal=1", "UPDATE functor_applications SET location=X'00' WHERE artifact='a.cmt' AND ordinal=1", "UPDATE functor_applications SET location='{}' WHERE artifact='a.cmt' AND ordinal=1", "UPDATE functor_applications SET head='{\"kind\":\"path\",\"compiler\":1,\"source\":\"F\",\"contains_apply\":false,\"extra\":true}' WHERE artifact='a.cmt' AND ordinal=1", "UPDATE functor_applications SET argument='{\"kind\":\"unit\"}' WHERE artifact='a.cmt' AND ordinal=1", "UPDATE functor_applications SET diagnostics='[\"unusable_location\",\"unusable_location\"]' WHERE artifact='a.cmt' AND ordinal=1", "UPDATE functor_applications SET head='{\"kind\":\"application\",\"ordinal\":1}' WHERE artifact='a.cmt' AND ordinal=1", "INSERT INTO functor_applications VALUES(1,'orphan.cmt',1,'apply','{}','{}','{}','[]')", "DELETE FROM functor_catalogue_inputs WHERE artifact='b.cmt'"
    ];
    mutationsSql.forEach((text, i) => { const db = path.join(dir, `bad-${i}.db`); makeDb(db); relaxedApplications(db); sql(db, text); expectInconsistent(db, text); });
    const unmarked = path.join(dir, 'unmarked.db'); makeDb(unmarked, "DELETE FROM comment_db_meta WHERE key='functor_catalogue_contract'; UPDATE functor_catalogue_inputs SET outcome='unreadable' WHERE artifact='b.cmt'"); assertRefusal(queryRun(unmarked), 'NOT_COLLECTED');
    const missing = path.join(dir, 'missing.db'); makeDb(missing, 'DROP TABLE functor_applications'); assertRefusal(queryRun(missing), 'UNSUPPORTED_SCHEMA');
    const missingColumn = path.join(dir, 'missing-column.db'); makeDb(missingColumn); sql(missingColumn, 'ALTER TABLE functor_applications DROP COLUMN diagnostics'); assertRefusal(queryRun(missingColumn), 'UNSUPPORTED_SCHEMA');
    const flat = path.join(dir, 'flat.db'); sql(flat, 'CREATE TABLE functions(id INTEGER); CREATE TABLE calls(id INTEGER); CREATE TABLE comment_db_meta(key TEXT,value TEXT);'); assertRefusal(queryRun(flat), 'UNSUPPORTED_SCHEMA');
    const unknown = path.join(dir, 'unknown-marker.db'); makeDb(unknown, "UPDATE comment_db_meta SET value='v2' WHERE key='functor_catalogue_contract'; UPDATE functor_catalogue_inputs SET outcome='unreadable' WHERE artifact='b.cmt'"); const unknownResult = queryRun(unknown); assertRefusal(unknownResult, 'NOT_COLLECTED'); assert.match(unknownResult.stderr, /unreadable/);
    const cancelled = path.join(dir, 'cancelled.db'); makeDb(cancelled, "UPDATE functor_catalogue_inputs SET expected_applications=CASE artifact WHEN 'a.cmt' THEN 1 ELSE 2 END"); expectInconsistent(cancelled, 'per-input counts cannot cancel');
    const badRun = path.join(dir, 'bad-run.db'); makeDb(badRun, 'UPDATE functor_catalogue_runs SET producer_run_id=99'); expectInconsistent(badRun, 'run header link');
    const cross = path.join(dir, 'cross.db'); makeDb(cross); relaxedApplications(cross); sql(cross, "UPDATE functor_applications SET argument='{\"kind\":\"application\",\"ordinal\":2}' WHERE artifact='b.cmt'"); expectInconsistent(cross, 'cross-input reference');
    const duplicateArtifact = path.join(dir, 'duplicate-artifact.db'); makeDb(duplicateArtifact); sql(duplicateArtifact, 'ALTER TABLE functor_catalogue_inputs RENAME TO functor_catalogue_inputs_checked; CREATE TABLE functor_catalogue_inputs AS SELECT * FROM functor_catalogue_inputs_checked; DROP TABLE functor_catalogue_inputs_checked; INSERT INTO functor_catalogue_inputs SELECT * FROM functor_catalogue_inputs WHERE artifact=\'a.cmt\''); expectInconsistent(duplicateArtifact, 'duplicate artifact');
    const fifty = path.join(dir, 'fifty.db'); makeDb(fifty); sql(fifty, "DELETE FROM functor_applications WHERE artifact='b.cmt'; DELETE FROM functor_catalogue_inputs WHERE artifact='b.cmt'; UPDATE functor_catalogue_runs SET selected_inputs=1; UPDATE functor_catalogue_inputs SET expected_applications=60; WITH RECURSIVE n(x) AS (VALUES(3) UNION ALL SELECT x+1 FROM n WHERE x<60) INSERT INTO functor_applications SELECT producer_run_id,artifact,x,application_kind,location,head,argument,diagnostics FROM functor_applications,n WHERE artifact='a.cmt' AND ordinal=1;");
    const fiftyResult = queryRun(fifty); assert.equal(fiftyResult.status, 0, fiftyResult.stderr); const [fiftySummary, fiftyRows] = twoArrays(fiftyResult.stdout); assert.equal(fiftySummary[0].total, 60); assert.equal(fiftySummary[0].returned, 50); assert.equal(fiftySummary[0].truncated, 1); assert.equal(fiftyRows.length, 50); successes++;
  });
  return {successes, mutations, formats: formats.length};
};
