// GET / PUT /api/local/settings（契约第三节）。
//
// GET 是纯只读：读文件、坏文件回退到缺省、把原因写进 sources，自身不写任何东西。
// PUT 走守卫 + 校验 + 原子写，返回落盘后的完整值。

///|
/// 设置响应体：values / defaults / sources 三件套（键序固定），外加存储路径与文件级提示。
async fn settings_payload(
  extra : Array[(String, @json.JsonVal)],
) -> @json.JsonVal noraise {
  let loaded = @store.load_settings()
  let paths = @store.state_paths()
  let defaults = @store.default_settings()
  let values : Array[(String, @json.JsonVal)] = []
  let default_fields : Array[(String, @json.JsonVal)] = []
  let sources : Array[(String, @json.JsonVal)] = []
  for key in @store.settings_keys() {
    values.push((key, @store.value_of(loaded.values, key)))
    default_fields.push((key, @store.value_of(defaults, key)))
    let source = match loaded.sources.get(key) {
      Some(s) => s
      None => "默认"
    }
    sources.push((key, @json.JStr(source)))
  }
  let fields : Array[(String, @json.JsonVal)] = [
    ("path", @json.JStr(paths.settings)),
    ("values", @json.JObj(values)),
    ("defaults", @json.JObj(default_fields)),
    ("sources", @json.JObj(sources)),
    ("note", @json.str_or_null(loaded.note)),
  ]
  for pair in extra {
    fields.push(pair)
  }
  @json.JObj(fields)
}

///|
/// GET /api/local/settings：纯只读，走只读外壳（readOnly: true）。
async fn handle_settings_get(
  res : @moonback.Responder,
  read_at : String,
) -> Unit {
  // 启动环境（§61）：与设置项分开存（env.json），但读的时候一起给界面，
  // 免得「设置页要发两次请求才凑齐一页」。
  let env = @store.load_env_file()
  let profiles_fields : Array[(String, @json.JsonVal)] = []
  for pair in env.profiles.iter() {
    profiles_fields.push((pair.0, @store.env_map_json(pair.1)))
  }
  let env_json = @json.JObj([
    ("path", @json.JStr(@store.env_file_path())),
    // 生效方式（§62.2）：前端按这两个字段渲染「继承系统环境」开关与「同名变量覆盖/追加」单选。
    // 缺省与 envfile 一致：继承 + 覆盖。
    (
      "options",
      @json.JObj([
        ("inherit", @json.JBool(env.options.keep_system)),
        ("merge", @json.JStr(env.options.merge)),
      ]),
    ),
    ("global", @store.env_map_json(env.global)),
    ("profiles", @json.JObj(profiles_fields)),
    // 保留键名单随读数一起给：界面据此置灰（§61.2）
    ("reserved", @json.jstr_array(@store.reserved_env_keys())),
  ])
  @localapi.send_ok(res, settings_payload([("env", env_json)]), read_at)
}

///|
/// PUT /api/local/settings。守卫 / 解析 / 校验 / 落盘，任何一步不过都回写侧错误壳。
async fn handle_settings_put(
  req : @moonback.Request,
  res : @moonback.Responder,
  read_at : String,
) -> Unit {
  authorize(req) catch {
    ActionError(code~, message~) => {
      send_write_error(res, code, message, read_at)
      return
    }
  }
  let body = req.body.text()
  let json = match @json.json_parse(body) {
    Some(j) => j
    None => {
      send_write_error(res, "bad-params", "body 不是合法 JSON", read_at)
      return
    }
  }
  let values = match @json.json_field(json, "values") {
    Some(v) => v
    None => {
      send_write_error(res, "bad-params", "body 里缺少 values", read_at)
      return
    }
  }
  let loaded = @store.load_settings()
  let updated = match @store.apply_patch(loaded.values, values) {
    Ok(next) => next
    Err(pair) => {
      send_write_error(res, pair.0, pair.1, read_at)
      return
    }
  }
  match @store.save_settings(updated) {
    Ok(_) => ()
    Err(e) => {
      // 原始 OSError 取一份带进回执（取一次就清，见 store/raw.mbt）：
      // message 说结论，raw 给排查用，界面默认不显示
      let raw = @store.take_raw()
      send_write_error(res, "io-error", e, read_at, raw~)
      return
    }
  }
  let changed : Array[String] = []
  for pair in @store.object_entries(values) {
    changed.push(pair.0)
  }
  let payload = settings_payload([
    ("changed", @json.jstr_array(changed)),
    ("readAt", @json.JStr(read_at)),
  ])
  // 设置写入也留一条审计：它是「写」，只是不属于那 8 个动作
  let _ = @store.append_audit(
    @store.audit_line(
      read_at,
      "put-settings",
      @json.JObj([("values", json_to_val(values))]),
      true,
      None,
      None,
      @json.JObj([("changed", @json.jstr_array(changed))]),
    ),
  )
  send_write_ok(res, payload, read_at)
}

///|
/// 设置端点的分发：GET 只读，PUT 写，别的方法 405。
pub async fn handle_settings(
  req : @moonback.Request,
  res : @moonback.Responder,
  read_at : String,
) -> Unit {
  let verb = @localapi.method_name(req.meth)
  match verb {
    "GET" => handle_settings_get(res, read_at)
    "PUT" => handle_settings_put(req, res, read_at)
    _ => send_method_not_allowed(res, "GET, PUT", verb, read_at)
  }
}
