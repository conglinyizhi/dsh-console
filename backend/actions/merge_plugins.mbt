// 插件合并：把一只 profile（通常是派生副本）里开发好的本地插件分发到别的 profile。
// design/backlog.md 的 N 条。这一版只做「拍快照 + 拷包 + 补 bundles」，
// cordis.patch.yml 不动（回执里明说），备注与环境变量也不跟过去。
//
// 认哪些是本地插件：node_modules/@local/* 下的条目（目录或软链），
// 以及 package.json 里用 file: / link: 声明的依赖。

///|
/// 一只目标的回执。
pub(all) struct MergeTarget {
  name : String
  ok : Bool
  error : String
  snapshot : String
  copied : Array[String]
  overwritten : Array[String]
  bundles_added : Array[String]
}

///|
/// 源 profile 里认出的本地插件。
struct LocalPlugin {
  name : String
  path : String
  is_link : Bool
}

///|
/// 两个绝对路径之间的相对路径（从 from_dir 出发）。
fn relative_from(from_dir : String, target : String) -> String {
  let a : Array[String] = []
  for s in from_dir.split("/") {
    a.push(@json.owned(s))
  }
  let b : Array[String] = []
  for s in target.split("/") {
    b.push(@json.owned(s))
  }
  let mut i = 0
  while i < a.length() && i < b.length() && a[i] == b[i] {
    i = i + 1
  }
  let parts : Array[String] = []
  let mut k = i
  while k < a.length() {
    if a[k].length() > 0 {
      parts.push("..")
    }
    k = k + 1
  }
  // b 从公共前缀之后开始接（不是接着 a 的游标）
  let mut j = i
  while j < b.length() {
    if b[j].length() > 0 {
      parts.push(b[j].to_string())
    }
    j = j + 1
  }
  if parts.length() == 0 {
    "."
  } else {
    parts.join("/")
  }
}

///|
/// 把路径里的 . 与 .. 段折掉（绝对路径）。
fn normalize_path(path : String) -> String {
  let parts : Array[String] = []
  for seg in path.split("/") {
    let s = @json.owned(seg)
    if s == "" || s == "." {
      continue
    }
    if s == ".." {
      if parts.length() > 0 {
        let _ = parts.pop()
      }
      continue
    }
    parts.push(s)
  }
  "/" + parts.join("/")
}

///|
/// 读一份插件的 package.json 拿 version（读不到给空串）。
async fn plugin_version(dir : String) -> String noraise {
  let text = match @json.read_text_file(@json.join_path(dir, "package.json")) {
    Ok(t) => t
    Err(_) => return ""
  }
  match @json.json_parse(text) {
    Some(pkg) =>
      match @json.json_field(pkg, "version") {
        Some(v) =>
          match @json.json_string(v) {
            Some(s) => s
            None => ""
          }
        None => ""
      }
    None => ""
  }
}

///|
/// GET /api/local/merge-preview?source=<profile>（只读）：这一步不写任何东西。
/// 识别口径与 merge-plugins 完全同一份（local_plugins_of），界面据此先选插件再选目标。
pub async fn merge_preview_json(source_in : String) -> @json.JsonVal raise ActionError {
  let source = @json.trim_both(source_in)
  if source == "" {
    fail("bad-params", "缺少 source（要看哪一只 profile 的本地插件）")
  }
  let (dir, _) = @profiles.profile_location(source)
  if !@json.is_dir(dir) {
    fail("not-found", "profile 目录不存在：" + dir)
  }
  let plugins = local_plugins_of(dir)
  let items : Array[@json.JsonVal] = []
  let warnings : Array[String] = []
  for plugin in plugins {
    let version = plugin_version(plugin.path)
    if version == "" {
      warnings.push(plugin.name + " 读不到 version（package.json 里没有或读不出来）")
    }
    items.push(
      @json.JObj([
        ("name", @json.JStr(plugin.name)),
        ("link", @json.JBool(plugin.is_link)),
        ("version", @json.JStr(version)),
      ]),
    )
  }
  @json.JObj([
    ("source", @json.JStr(source)),
    ("plugins", @json.JArr(items)),
    ("warnings", @json.jstr_array(warnings)),
  ])
}

///|
/// 从 node_modules/@local 与 package.json 的 file:/link: 依赖里认本地插件。
async fn local_plugins_of(dir : String) -> Array[LocalPlugin] noraise {
  let out : Array[LocalPlugin] = []
  let seen : Array[String] = []
  let local_dir = @json.join_all([dir, "node_modules", "@local"])
  if @json.is_dir(local_dir) {
    // list_dir 只给目录名，路径得自己拼回来
    for name in @json.list_dir(local_dir) {
      if name == "" || seen.contains(name) {
        continue
      }
      let entry = @json.join_path(local_dir, name)
      let is_link = match @json.read_link(entry) {
        Ok(_) => true
        Err(_) => false
      }
      if is_link || @json.is_dir(entry) {
        // node_modules/@local/<dir> 的包名是带 scope 的 "@local/<dir>"（bundle 就按这个写）
        let full = "@local/" + name
        seen.push(full)
        out.push({ name: full, path: entry, is_link })
      }
    }
  }
  // package.json 里以 file: / link: 声明的依赖（可能还没装到 node_modules）
  let text = match @json.read_text_file(@json.join_path(dir, "package.json")) {
    Ok(t) => t
    Err(_) => ""
  }
  if text != "" {
    match @json.json_parse(text) {
      Some(pkg) =>
        match @json.json_field(pkg, "dependencies") {
          Some(deps) =>
            for pair in @store.object_entries(deps) {
              let spec = match @json.json_string(pair.1) {
                Some(s) => s
                None => continue
              }
              if !spec.has_prefix("file:") && !spec.has_prefix("link:") {
                continue
              }
              let name = pair.0
              if seen.contains(name) {
                continue
              }
              let rel = @json.slice(spec, 5, spec.length())
              let path = if rel.has_prefix("/") {
                rel
              } else {
                @json.join_path(dir, rel)
              }
              if @json.exists(path) {
                seen.push(name)
                out.push({ name, path, is_link: false })
              }
            }
          None => ()
        }
      None => ()
    }
  }
  out
}

///|
/// 把一个插件摆进目标 node_modules/@local/<name>：软链按 §48 的口径重算相对路径，
/// 目录整份拷过去。返回是否覆盖了已有的同名条目（「覆盖前在清单里写明」用）。
async fn place_plugin(plugin : LocalPlugin, target_dir : String) -> Result[Bool, String] noraise {
  let dest_dir = @json.join_all([target_dir, "node_modules", "@local"])
  match @fsx.ensure_dir(dest_dir) {
    Ok(_) => ()
    Err(e) => return Err(e)
  }
  let dest = @json.join_path(dest_dir, @json.basename(plugin.name))
  let mut overwritten = false
  if @json.exists(dest) {
    overwritten = true
    let dest_is_link = match @json.read_link(dest) {
      Ok(_) => true
      Err(_) => false
    }
    let removed = if dest_is_link {
      @fsx.remove_file(dest)
    } else {
      @fsx.remove_tree(dest)
    }
    match removed {
      Ok(_) => ()
      Err(e) => return Err("删不掉目标里已有的 " + dest + "：" + e)
    }
  }
  if plugin.is_link {
    let resolved = match @json.read_link(plugin.path) {
      Ok(raw) =>
        if raw.has_prefix("/") {
          raw
        } else {
          // 相对链接按链接自身所在目录解析（§48 同一口径）
          normalize_path(@json.join_path(@json.dirname(plugin.path), raw))
        }
      Err(_) => plugin.path
    }
    let rel = relative_from(dest_dir, resolved)
    return match @fsx.make_symlink(rel, dest) {
      Ok(_) => Ok(overwritten)
      Err(e) => Err("建不了软链 " + dest + "：" + e)
    }
  }
  match @fsx.copy_tree(plugin.path, dest, []) {
    Ok(_) => Ok(overwritten)
    Err(e) => Err("拷不动 " + plugin.path + "：" + e)
  }
}

///|
/// 从解析好的 package.json 里取 dsh.profile.bundles。
fn declared_bundles_text(pkg : Json) -> Array[String] {
  let out : Array[String] = []
  let dsh = match @json.json_field(pkg, "dsh") {
    Some(v) => v
    None => return out
  }
  let profile = match @json.json_field(dsh, "profile") {
    Some(v) => v
    None => return out
  }
  let bundles = match @json.json_field(profile, "bundles") {
    Some(v) => v
    None => return out
  }
  for item in @json.json_array(Some(bundles)) {
    match @json.json_string(item) {
      Some(s) => out.push(s)
      None => ()
    }
  }
  out
}

///|
/// 从 text 里 open_at 这个 '[' 起找配对的 ']'（跳过字符串里的括号）。
fn match_array_end(text : String, open_at : Int) -> Int? {
  let mut depth = 0
  let mut i = 0
  let mut in_string = false
  let mut escaped = false
  for c in text {
    if i >= open_at {
    if in_string {
      if escaped {
        escaped = false
      } else if c == '\\' {
        escaped = true
      } else if c == '"' {
        in_string = false
      }
    } else if c == '"' {
      in_string = true
    } else if c == '[' {
      depth = depth + 1
    } else if c == ']' {
      depth = depth - 1
      if depth == 0 {
        return Some(i)
      }
    }
    }
    i = i + 1
  }
  None
}

///|
/// 把包名补进 package.json 的 dsh.profile.bundles（已在就跳过）。
/// 文本级插入再回读校验：不重排整份 JSON，也不动别的字段。
fn bundles_with(names : Array[String], text : String) -> Result[(Array[String], String), String] {
  let json = match @json.json_parse(text) {
    Some(j) => j
    None => return Err("package.json 不是合法 JSON")
  }
  let existing = declared_bundles_text(json)
  let missing : Array[String] = []
  for name in names {
    if !existing.contains(name) {
      missing.push(name)
    }
  }
  if missing.length() == 0 {
    return Ok(([], text))
  }
  let key_at = match @json.index_of(text, "\"bundles\"") {
    Some(i) => i
    None => return Err("package.json 里没有 dsh.profile.bundles")
  }
  let open_rel = match @json.index_of(@json.slice(text, key_at, text.length()), "[") {
    Some(i) => i
    None => return Err("bundles 不是数组")
  }
  let open_at = key_at + open_rel
  let close_at = match match_array_end(text, open_at) {
    Some(i) => i
    None => return Err("bundles 数组没有收尾")
  }
  let inner = @json.trim_both(@json.slice(text, open_at + 1, close_at))
  let quoted : Array[String] = []
  for name in missing {
    quoted.push("\"" + name + "\"")
  }
  let inserted = if inner == "" {
    quoted.join(", ")
  } else {
    ", " + quoted.join(", ")
  }
  let new_text = @json.slice(text, 0, close_at) + inserted + @json.slice(text, close_at, text.length())
  match @json.json_parse(new_text) {
    Some(_) => Ok((missing, new_text))
    None => Err("改完的 package.json 解析不了，已放弃写入")
  }
}

///|
/// merge-plugins：params { profile, targets: [..], confirm }。
pub async fn merge_plugins_action(params : Json) -> @json.JsonVal raise ActionError {
  ensure_action_params(params, "分发插件：", ["profile", "targets", "plugins", "confirm"])
  let confirm = require_string(params, "confirm")
  if confirm != "MERGE" {
    fail(
      "bad-params",
      "确认串不对：要原样输入 MERGE 才会分发（你给的是「" + confirm + "」）",
    )
  }
  let source_name = @json.trim_both(require_string(params, "profile"))
  validate_profile_name(source_name)
  let (source_dir, _) = @profiles.profile_location(source_name)
  if !@json.is_dir(source_dir) {
    fail("not-found", "源 profile 目录不存在：" + source_dir)
  }
  let all_plugins = local_plugins_of(source_dir)
  // 只分发参数里点名的这几个（§N 第二版）；不给就是全部（向后兼容）
  let plugins : Array[LocalPlugin] = []
  match @json.json_field(params, "plugins") {
    Some(list) => {
      let names : Array[String] = []
      for item in @json.json_array(Some(list)) {
        match @json.json_string(item) {
          Some(s) => names.push(@json.trim_both(s))
          None => ()
        }
      }
      let available : Array[String] = []
      for p in all_plugins {
        available.push(p.name)
      }
      for name in names {
        let mut hit = false
        for p in all_plugins {
          if p.name == name {
            plugins.push(p)
            hit = true
          }
        }
        if !hit {
          fail(
            "bad-params",
            "这只源里没有插件「" + name + "」；可选的是：" + available.join("、"),
          )
        }
      }
    }
    None => {
      for p in all_plugins {
        plugins.push(p)
      }
    }
  }
  if plugins.length() == 0 {
    fail(
      "not-found",
      source_name + " 里没有本地插件（node_modules/@local 与 file:/link: 依赖都是空的）",
    )
  }
  let targets : Array[String] = []
  for item in @json.json_array(@json.json_field(params, "targets")) {
    let name = match @json.json_string(item) {
      Some(s) => @json.trim_both(s)
      None => ""
    }
    if name == "" || name == source_name || targets.contains(name) {
      continue
    }
    targets.push(name)
  }
  if targets.length() == 0 {
    fail("bad-params", "没有可分发到的目标（至少选一只别的 profile）")
  }
  let reports : Array[MergeTarget] = []
  for target_name in targets {
    reports.push(merge_into(source_name, source_dir, plugins, target_name))
  }
  let mut ok_count = 0
  for r in reports {
    if r.ok {
      ok_count = ok_count + 1
    }
  }
  @json.JObj([
    ("action", @json.JStr("merge-plugins")),
    (
      "outcome",
      @json.JObj([
        ("source", @json.JStr(source_name)),
        (
          "plugins",
          @json.JArr(
            plugins.map(fn(p) {
              @json.JObj([("name", @json.JStr(p.name)), ("link", @json.JBool(p.is_link))])
            }),
          ),
        ),
        ("targets", @json.JArr(reports.map(merge_target_json))),
        ("okCount", @json.jint(ok_count)),
        ("failedCount", @json.jint(reports.length() - ok_count)),
        // cordis.patch.yml 这一版不动：回执必须明说，免得以为合并过了
        ("patchesTouched", @json.JBool(false)),
      ]),
    ),
    (
      "note",
      @json.JStr(
        "分发了 " + ok_count.to_string() + "/" + reports.length().to_string() + " 只；" +
        (if ok_count == reports.length() {
          ""
        } else {
          let bad : Array[String] = []
          for r in reports {
            if !r.ok {
              bad.push(r.name + "：" + r.error)
            }
          }
          "失败 " + bad.join("；") + "。"
        }) +
        "cordis.patch.yml 这一版没有动（要改覆盖项得手动）。",
      ),
    ),
  ])
}

///|
/// 往一只目标里分发：拍快照 → 拷包 → 补 bundles。任何一步出问题只影响这一只。
async fn merge_into(
  source_name : String,
  source_dir : String,
  plugins : Array[LocalPlugin],
  target_name : String,
) -> MergeTarget noraise {
  let report : MergeTarget = {
    name: target_name,
    ok: false,
    error: "",
    snapshot: "",
    copied: [],
    overwritten: [],
    bundles_added: [],
  }
  let (target_dir, _) = @profiles.profile_location(target_name)
  if !@json.is_dir(target_dir) {
    return { ..report, error: "目标 profile 不存在：" + target_dir }
  }
  if target_dir == source_dir {
    return { ..report, error: "目标与源是同一只 profile" }
  }
  // 1) 先拍快照（复用现有 snapshot 那套；拍不成就不动这只目标）
  let snapshot = match @profiles.create_snapshot(target_dir, "分发插件前：" + source_name, keep_id="merge") {
    Ok(outcome) => outcome.id
    Err(e) => return { ..report, error: "拍不了快照，这一只没动：" + e }
  }
  // 2) 逐个拷包
  let copied : Array[String] = []
  let overwritten : Array[String] = []
  for plugin in plugins {
    match place_plugin(plugin, target_dir) {
      Ok(replaced) => {
        copied.push(plugin.name)
        if replaced {
          overwritten.push(plugin.name)
        }
      }
      Err(e) => return { ..report, snapshot, copied, overwritten, error: e }
    }
  }
  // 3) 补 bundles
  let pkg_path = @json.join_path(target_dir, "package.json")
  let text = match @json.read_text_file(pkg_path) {
    Ok(t) => t
    Err(e) => return { ..report, snapshot, copied, overwritten, error: "读不了目标 package.json：" + e }
  }
  let names = plugins.map(fn(p) { p.name })
  match bundles_with(names, text) {
    Ok((added, new_text)) => {
      if added.length() > 0 {
        match @fsx.write_text_atomic(pkg_path, new_text) {
          Ok(_) => ()
          Err(e) =>
            return { ..report, snapshot, copied, overwritten, error: "写不进目标 package.json：" + e }
        }
      }
      { ..report, snapshot, copied, overwritten, bundles_added: added, ok: true }
    }
    Err(e) => { ..report, snapshot, copied, overwritten, error: e }
  }
}

///|
fn merge_target_json(r : MergeTarget) -> @json.JsonVal {
  @json.JObj([
    ("name", @json.JStr(r.name)),
    ("ok", @json.JBool(r.ok)),
    ("error", @json.JStr(r.error)),
    ("snapshot", @json.JStr(r.snapshot)),
    ("copied", @json.jstr_array(r.copied)),
    ("overwritten", @json.jstr_array(r.overwritten)),
    ("bundlesAdded", @json.jstr_array(r.bundles_added)),
  ])
}
///|
/// POST /api/local/merge-preview 的入口（只读：不写任何东西，只是把源的插件清单读一遍）。
/// 为什么用 POST 而不是 GET + 查询串：moonback 路由把查询串剥掉了，req.path 里只剩路径；
/// POST 走 body 与 settings 那套同形，前端也不用自己拼 URL。
pub async fn handle_merge_preview(
  req : @moonback.Request,
  res : @moonback.Responder,
  read_at : String,
) -> Unit {
  let verb = @localapi.method_name(req.meth)
  if verb != "POST" {
    send_method_not_allowed(res, "POST", verb, read_at)
    return
  }
  let json = match @json.json_parse(req.body.text()) {
    Some(j) => j
    None => {
      send_write_error(res, "bad-params", "body 不是合法 JSON", read_at)
      return
    }
  }
  let source = match @json.json_field(json, "source") {
    Some(v) =>
      match @json.json_string(v) {
        Some(s) => s
        None => ""
      }
    None => ""
  }
  let data = try {
    merge_preview_json(source)
  } catch {
    ActionError(code~, message~) => {
      send_write_error(res, code, message, read_at)
      return
    }
  }
  @localapi.send_ok(res, data, read_at)
}

