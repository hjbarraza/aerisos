// Print a map's data.js as JSON: {CONFIG, SRC, DOMAINS, KINDS, CONF, REL, NODES, E, ENRICH}.
//   node dump_data.js ~/maps/<map>/data/data.js
const fs = require("fs"), vm = require("vm");
const src = fs.readFileSync(process.argv[2], "utf8");
const names = ["CONFIG", "SRC", "DOMAINS", "KINDS", "CONF", "REL", "NODES", "E", "ENRICH"];
const ctx = {};
vm.runInNewContext(src + "\n;globalThis.__out = {" + names.map(n => `${n}: typeof ${n} === "undefined" ? null : ${n}`).join(",") + "};", ctx);
process.stdout.write(JSON.stringify(ctx.__out));
