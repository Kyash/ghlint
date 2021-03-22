#!/usr/bin/env node

(() => {
  URL.prototype.toJSON = function (key) {
    this.searchParams.toJSON = function (key) {
      const o = {};
      for (const [key, value] of this) o[key] = value;
      return o;
    };
    const o = {};
    for (const key in this) if (!/^to(JSON|String)/.test(key)) o[key] = this[key];
    return o;
  };

  (async (args) => {
    if (args.length > 0) return args;
    const buffers = [];
    for await (const chunk of process.stdin) buffers.push(chunk);
    const buffer = Buffer.concat(buffers);
    const text = buffer.toString();
    const lines = text.split(/\r?\n|\r/);
    const last = lines.pop();
    if (last) lines.push(last);
    return lines;
  })(process.argv.slice(2)).then(values => values.map(value => new URL(value)).forEach(url => {
    process.stdout.write('\x1e');
    process.stdout.write(JSON.stringify(url));
    process.stdout.write('\n');
  })).catch(error => {
    console.error(error.message);
    process.exit(1);
  });
})();
