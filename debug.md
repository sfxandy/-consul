```bash

- name: GMT discovery | summarize _gmt_slurp (safe)
  set_fact:
    _gmt_slurp_summary:
      exists: "{{ _gmt_file.stat.exists | default(false) }}"
      defined: "{{ _gmt_slurp is defined }}"
      b64_len: "{{ (_gmt_slurp.content | default('')) | length }}"
      b64_sha256: "{{ (_gmt_slurp.content | default('') ) | hash('sha256') }}"
  when: consul_gmt_debug | bool
  run_once: true
  tags: [always]

- name: GMT discovery | show summary (safe)
  debug:
    var: _gmt_slurp_summary
  when: consul_gmt_debug | bool
  run_once: true
  tags: [always]

```
