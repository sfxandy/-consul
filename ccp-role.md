```bash

DEFAULTS
--------

# Resolve HOME and XDG roots
consul_home_dir: "{{ ansible_env.HOME }}"
xdg_config_home: "{{ ansible_env.XDG_CONFIG_HOME | default(consul_home_dir + '/.config', true) }}"
xdg_data_home:   "{{ ansible_env.XDG_DATA_HOME   | default(consul_home_dir + '/.local/share', true) }}"
xdg_state_home:  "{{ ansible_env.XDG_STATE_HOME  | default(consul_home_dir + '/.local/state', true) }}"

# Base (app) roots
consul_base_config_dir: "{{ xdg_config_home }}/consul"
consul_base_data_dir:   "{{ xdg_data_home   }}/consul"
consul_base_state_dir:  "{{ xdg_state_home  }}/consul"

# Instances co-located on the same host
# You can add more (e.g., "wan", "dev", etc.) by adding entries.
consul_instances:
  - id: "server"
    container: "consul-server"
  - id: "agent"
    container: "consul-agent"

# Executables dir
consul_bin_dir: "{{ ansible_env.XDG_BIN_HOME | default(consul_home_dir + '/.bin', true) }}"

# Wrapper options
consul_install_cli_wrapper: true
# Which instance the generic "consul" wrapper points to:
consul_default_wrapper_instance: "agent"

# Add bin dir to PATH
consul_manage_shell_path: true
consul_shell_rc_files:
  - "{{ consul_home_dir }}/.bashrc"
  - "{{ consul_home_dir }}/.zshrc"




TASKS
-----

- name: "Create per-instance directories"
  become: false
  vars:
    inst_cfg:  "{{ consul_base_config_dir }}/{{ item.id }}"
    inst_data: "{{ consul_base_data_dir   }}/{{ item.id }}"
    inst_log:  "{{ consul_base_state_dir  }}/{{ item.id }}/log"
  loop: "{{ consul_instances }}"
  loop_control: { label: "{{ item.id }}" }
  ansible.builtin.file:
    path: "{{ item2 }}"
    state: directory
    mode: "0755"
  with_items:
    - "{{ inst_cfg }}"
    - "{{ inst_data }}"
    - "{{ inst_log }}"
  loop_control:
    loop_var: item2





















```
