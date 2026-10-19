// 隔离 home：每只 profile 一个 <DSH_CONSOLE_HOMES_ROOT>/<profile>/
//
// 口径见 design/deep-home-isolation.md 第 2、3、7 节：
//
//   <root>/<profile>/
//     profiles/<profile>/            从 <DSH_HOME>/profiles/<profile> 复制：
//                                      cordis.yml / cordis.patch.yml / package.json /
//                                      pnpm-workspace.yaml（源里有才复制）
//         node_modules -> 源 profile 的 node_modules（源里没有就退到 profiles/node_modules）
//     skills/                        -> <DSH_HOME>/skills（软链；技能共享更合理）
//     logs/                          空目录，实例日志落这儿
//     .dsh-console-isolation.json    这一份是什么时候、从哪个 home 建的（读数里的 createdAt 用它）
//
// 凭证**不复制、不软链**（规格 2.2 记着实测的坑：软链会被 dsh 的原子写 rename 换成明文副本，
// 每个 home 里就多一份密钥）。这里只把路径写进 profiles/<profile>/cordis.patch.yml 的一条
// credentials 配置里 —— 具体键按这一版 dsh 的 schema 定：
//   dsh --profile <名字> --dump-config-schema
// 里 credentials（@deepseek-ai/dsh-credentials-local）的 config 是
//   { path, dshHome, watch, debounceMs }
// 所以写的是 config.path（见 add_credentials_patch 上方的注释）。
//
// 硬约束（规格第 7 节）：
//   · 只建 homes root 下的目录，且目标必须正好是 <root>/<单段 profile 名>；
//   · 删只删这个口径拼出来的目录，不接收客户端给的路径；
//   · 复制完要核对（package.json 读得出来 / node_modules 软链指得通 / cordis.patch.yml 在），
//     任何一条不过就删掉刚建的目录并报失败 —— 不留半成品。

///|
/// homes root 的环境变量。
pub let homes_root_env : String = "DSH_CONSOLE_HOMES_ROOT"

///|
/// 隔离记录文件名（放在隔离 home 根下）。读数里的 createdAt 取它；
/// 没有这个文件时退回 home 目录的 mtime，并在依据里说清是退回的。
pub let isolation_marker : String = ".dsh-console-isolation.json"

///|
/// 读数里的两档归属。
pub let home_kind_isolated : String = "isolated"
pub let home_kind_shared : String = "shared"

///|
/// 试跑一次性 home 的前缀（design/deep-home-isolation.md 第 6 节）。
/// 建与删都只认这个前缀：homes root 下别人摆的东西一个都碰不到。
pub let trial_home_prefix : String = "trial-"

///|
/// 试跑 home 在读数 / 作业里的归属词（与 isolated / shared 并列的第三档）。
pub let home_kind_trial : String = "trial"

///|
/// 从源 profile 复制的四份配置（有才复制，缺的文件不算错）。
let profile_config_files : Array[String] = [
  "cordis.yml",
  "cordis.patch.yml",
  "package.json",
  "pnpm-workspace.yaml",
]

///|
/// 凭证配置那一条 patch entry 的 id。dsh 这一版用它挂
/// @deepseek-ai/dsh-credentials-local（--dump-config-schema 输出里的 /24 那条）。
let credentials_entry_id : String = "credentials"

///|
/// 去掉末尾的斜杠（保留根 /）。
fn trim_tail_slash(path : String) -> String {
  let mut end = path.length()
  while end > 1 && @json.slice(path, end - 1, end) == "/" {
    end = end - 1
  }
  @json.slice(path, 0, end)
}

///|
/// homes root：$DSH_CONSOLE_HOMES_ROOT（只认绝对路径），缺省 ~/.dsh-homes。
/// 返回 (路径, 来源)。来源进读数的依据那句话，不另编。
pub async fn homes_root() -> (String, String) noraise {
  let fallback = @json.join_path(@json.home_dir(), ".dsh-homes")
  match @json.env_value(homes_root_env) {
    Some(raw) => {
      let text = @json.trim_both(raw)
      if text.has_prefix("/") {
        (trim_tail_slash(text), homes_root_env + " 环境变量")
      } else {
        (fallback, "默认 ~/.dsh-homes（" + homes_root_env + " 不是绝对路径，按未设置处理）")
      }
    }
    None => (fallback, "默认 ~/.dsh-homes")
  }
}

///|
/// profile 名是不是单段（不含 / 与 ..，非空）。建 / 删隔离 home 之前必过这一道：
/// 一个能带斜杠的名字就足以让拼出来的路径跑到 homes root 之外。
pub fn single_segment(name : String) -> Bool {
  if name == "" || name == "." || name == ".." {
    return false
  }
  if @json.index_of(name, "/") is Some(_) {
    return false
  }
  if @json.index_of(name, "\\\\") is Some(_) {
    return false
  }
  true
}

///|
/// 隔离 home 的路径（不判断存在）。
pub fn isolated_home_dir(root : String, name : String) -> String {
  @json.join_path(root, name)
}

///|
/// 这只 profile 的隔离 home 是否已经在磁盘上（判据：<root>/<名字>/profiles/<名字> 是目录）。
pub async fn isolated_home_of(name : String) -> String? noraise {
  let (root, _) = homes_root()
  let home = isolated_home_dir(root, name)
  if @json.is_dir(@json.join_all([home, "profiles", name])) {
    Some(home)
  } else {
    None
  }
}

///|
/// 起实例该用哪个 home：(路径, isolated | shared)。
/// 有隔离 home 就用它；没有就用控制台的 DSH_HOME（此时读数与界面标「共用」）。
pub async fn default_home_of(name : String) -> (String, String) noraise {
  match isolated_home_of(name) {
    Some(home) => (home, home_kind_isolated)
    None => {
      let (dsh_home, _) = @runtime.resolve_dsh_home()
      (dsh_home, home_kind_shared)
    }
  }
}

///|
/// 一条 home 路径是不是试跑用的一次性 home：在 homes root 下，且目录名以 trial- 开头。
///
/// 判据只看路径本身，不读目录里的记录文件：读数要回答的是「这一只跑在哪份 home 里」，
/// 而记录文件可能还没写、也可能已经被删。
pub async fn is_trial_home(path_in : String) -> Bool noraise {
  let path = trim_tail_slash(@json.trim_both(path_in))
  if path == "" {
    return false
  }
  let (root, _) = homes_root()
  let prefix = root + "/"
  if !path.has_prefix(prefix) {
    return false
  }
  let name = @json.slice_from(path, prefix.length())
  single_segment(name) && name.has_prefix(trial_home_prefix)
}

///|
/// 按实际用的 home 路径判归属：trial / isolated / shared。
///
/// trial 先判（homes root 下 trial- 前缀）；其余与 default_home_of 同一把尺子：
/// 正好是这只 profile 的隔离 home 就是 isolated，别的（含控制台的 DSH_HOME）是 shared。
pub async fn home_kind_of(home_in : String, profile : String) -> String noraise {
  if is_trial_home(home_in) {
    return home_kind_trial
  }
  match isolated_home_of(profile) {
    Some(isolated) =>
      if trim_tail_slash(@json.trim_both(home_in)) == isolated {
        home_kind_isolated
      } else {
        home_kind_shared
      }
    None => home_kind_shared
  }
}

///|
/// 一只 profile 的 home 读数（GET /api/local/profiles 里每只一项）。
///
///   kind         isolated / shared
///   path         isolated = 隔离 home 根；shared = 控制台的 DSH_HOME
///   profile_dir  path/profiles/<名字>（实例真正从哪儿读配置）
///   created_at   隔离记录里的时刻；没有记录就退回 home 目录 mtime，读不到给 None
///   source       一句判断依据（进 homeKindSource）
pub(all) struct HomeFact {
  kind : String
  path : String
  profile_dir : String
  created_at : String?
  source : String
}

///|
/// 读隔离记录里的 createdAt。没有记录 / 读不动 → (None, 说明)；有记录 → (时刻, 空串)。
async fn marker_created_at(home : String) -> (String?, String) noraise {
  let path = @json.join_path(home, isolation_marker)
  match @json.read_text_file(path) {
    Err(_) => (None, "")
    Ok(text) =>
      match @json.json_parse(text) {
        None => (None, "")
        Some(json) =>
          match @json.json_field(json, "createdAt") {
            Some(value) =>
              match @json.json_string(value) {
                Some(stamp) => (Some(stamp), "")
                None => (None, "")
              }
            None => (None, "")
          }
      }
  }
}

///|
/// 隔离 home 的 createdAt：优先隔离记录，没有就退回 home 目录的 mtime（并在依据里写明）。
/// 两条都读不到给 None —— 不拿当前时间冒充「建于」。
async fn home_created_at(home : String) -> (String?, String) noraise {
  match marker_created_at(home) {
    (Some(stamp), _) => (Some(stamp), "")
    (None, _) =>
      match @json.mtime_ms(home) {
        Some(ms) =>
          (
            Some(@json.iso_from_epoch_ms(ms)),
            "；createdAt 取 " + home + " 目录的 mtime（没有隔离记录文件）",
          )
        None => (None, "；createdAt 读不到（没有隔离记录文件，" + home + " 也读不到 mtime）")
      }
  }
}

///|
/// 一只 profile 的 home 读数（控制台的 home 自己解析）。
pub async fn home_fact_of(name : String) -> HomeFact noraise {
  let (dsh_home, dsh_home_source) = @runtime.resolve_dsh_home()
  home_fact_in(name, dsh_home, dsh_home_source)
}

///|
/// 一只 profile 的 home 读数 + 判断依据。dsh_home 由调用方给（读数与 profiles 接口
/// 用同一份，不在两处各解析一遍）。
pub async fn home_fact_in(
  name : String,
  dsh_home : String,
  dsh_home_source : String,
) -> HomeFact noraise {
  let (root, root_source) = homes_root()
  let home = isolated_home_dir(root, name)
  let pdir = @json.join_all([home, "profiles", name])
  if @json.is_dir(pdir) {
    let (created, created_source) = home_created_at(home)
    {
      kind: home_kind_isolated,
      path: home,
      profile_dir: pdir,
      created_at: created,
      source: "隔离 home 在：" + pdir + "（homes root 来自 " + root_source + "：" + root +
      "）" + created_source,
    }
  } else {
    {
      kind: home_kind_shared,
      path: dsh_home,
      profile_dir: @json.join_all([dsh_home, "profiles", name]),
      created_at: None,
      source: "没有隔离 home（" + pdir + " 不存在），用控制台的 home " + dsh_home + "（" +
      dsh_home_source + "）；createdAt 只在隔离 home 里有意义",
    }
  }
}

///|
/// 一次隔离的结果。
pub(all) struct IsolateOutcome {
  profile : String
  /// 隔离 home 根：<root>/<名字>
  path : String
  /// 配置目录：<root>/<名字>/profiles/<名字>
  profile_dir : String
  /// 真复制过去的配置份数
  files_copied : Int
  /// node_modules 软链指向哪儿
  node_modules_target : String
  /// skills 软链摆上了吗（源 <DSH_HOME>/skills 不存在时不摆）
  skills_linked : Bool
  /// 凭证路径（写进 cordis.patch.yml 那一条 config.path 的值）
  credentials_path : String
  /// 用的配置键（证据里要说清是哪一个键）
  credentials_key : String
  created_at : String?
}

///|
/// 一次取消隔离的结果。
pub(all) struct DeisolateOutcome {
  profile : String
  path : String
  /// 删之前数出来的文件数与字节数；数不到给 None + 原因
  files : Int?
  bytes : Int64?
  size_source : String
}

///|
/// 回滚：删掉刚建的 home，并把原因写成一句人话。删不掉也要说出来（不假装收干净了）。
async fn rollback(
  home : String,
  code : String,
  message : String,
) -> Result[IsolateOutcome, (String, String)] noraise {
  let note = match @fsx.remove_tree(home) {
    Ok(_) => "；刚建的 " + home + " 已删掉（没有留下半成品）"
    Err(e) => "；刚建的 " + home + " 没能删掉：" + e
  }
  Err((code, message + note))
}

///|
/// YAML 双引号标量。路径里可能有空格，直接裸写会读歪；引号与反斜杠转义一次。
fn yaml_quote(text : String) -> String {
  let buf = StringBuilder()
  buf.write_char('"')
  for ch in text {
    if ch == '"' || ch == '\\' {
      buf.write_char('\\')
    }
    buf.write_char(ch)
  }
  buf.write_char('"')
  buf.to_string()
}

///|
/// 往隔离 home 的 cordis.patch.yml 里补一条凭证路径。
///
/// 键的来历：dsh --profile <名字> --dump-config-schema 里
/// credentials（@deepseek-ai/dsh-credentials-local）的 config schema 有 path / dshHome /
/// watch / debounceMs 四项，其中 path 就是凭证文件的位置。所以写：
///
///   - id: credentials
///     config:
///       path: "<DSH_HOME>/.credentials.yaml"
///
/// 源 patch 是空数组占位（只有注释与一个 []）时，那个 [] 要先去掉：
/// 它已经是根节点，后面再接一条 entry 就不是同一个 YAML 文档了（headless 这类 profile 就是这样）。
async fn add_credentials_patch(path : String, cred_path : String) -> Result[Unit, String] noraise {
  let existing = match @json.read_text_file(path) {
    Ok(text) => text
    Err(_) => ""
  }
  let kept : Array[String] = []
  for line in existing.split("\n") {
    let text = @json.trim_both(@json.owned(line))
    if text == "[]" {
      continue
    }
    kept.push(@json.owned(line))
  }
  let mut body = kept.join("\n")
  while body.length() > 0 && body.has_suffix("\n") {
    body = body[:body.length() - 1].to_owned()
  }
  let head = "# 隔离 home 的凭证只给路径：不复制、不软链（软链会被原子写换成明文副本，" +
    "每个 home 里就多一份密钥）。\n" +
    "# 这一条由 dsh-console 的隔离动作写进来；密钥本身留在 " + cred_path + "。\n"
  let block = "- id: " + credentials_entry_id + "\n" +
    "  config:\n" +
    "    path: " + yaml_quote(cred_path) + "\n"
  let text = if body == "" { head + block } else { body + "\n" + head + block }
  @fsx.write_text_atomic(path, text)
}

///|
/// 复制完的核对：package.json 读得出来、node_modules 软链指得通、cordis.patch.yml 在。
/// 任何一条不过给 Some(原因)，调用方据此回滚。
async fn verify_isolated(pdir : String, nm_target : String) -> String? noraise {
  let pkg = @json.join_path(pdir, "package.json")
  match @json.read_text_file(pkg) {
    Err(e) => return Some("复制过去的 package.json 读不出来：" + pkg + "（" + e + "）")
    Ok(text) =>
      match @json.json_parse(text) {
        Some(_) => ()
        None => return Some("复制过去的 package.json 不是合法 JSON：" + pkg)
      }
  }
  let link = @json.join_path(pdir, "node_modules")
  if !@json.is_dir(link) {
    return Some("node_modules 软链指不到目录：" + link + " -> " + nm_target)
  }
  match @json.read_link(link) {
    Err(e) => return Some("node_modules 软链读不出目标：" + link + "（" + e + "）")
    Ok(target) =>
      if target != nm_target {
        return Some("node_modules 软链指向 " + target + "，不是 " + nm_target)
      }
  }
  let patch = @json.join_path(pdir, "cordis.patch.yml")
  if !@json.exists(patch) {
    return Some("cordis.patch.yml 不在：" + patch)
  }
  None
}

///|
/// 一次「铺 home」的结果：复制了几份配置、软链指向哪儿、凭证路径写成了什么。
pub(all) struct HomeLayout {
  files_copied : Int
  node_modules_target : String
  skills_linked : Bool
  credentials_path : String
  credentials_key : String
}

///|
/// 按规格第 2 节铺一份 home（隔离 home 与试跑一次性 home 共用这一份铺法）：
///   profiles/<名字>/   复制源 profile 的 cordis.yml / cordis.patch.yml / package.json /
///                      pnpm-workspace.yaml（有才复制），node_modules 软链指源里那一份
///   skills/            -> <DSH_HOME>/skills（源里有才摆）
///   logs/              空目录，实例日志落这儿
///   凭证               只把路径写进 profiles/<名字>/cordis.patch.yml，不复制密钥
///
/// 任何一步失败都把 (错误码, 原因) 交回去；**删半成品目录由调用方做** ——
/// 两种 home（隔离 / 试跑）收尾时要说的话不一样。
async fn layout_home(
  home : String,
  name : String,
  src_dir : String,
  dsh_home : String,
) -> Result[HomeLayout, (String, String)] noraise {
  let pdir = @json.join_all([home, "profiles", name])
  match @fsx.ensure_dir(pdir) {
    Ok(_) => ()
    Err(e) => return Err(("io-error", e))
  }
  let mut copied = 0
  for file in profile_config_files {
    let from = @json.join_path(src_dir, file)
    if @json.exists(from) {
      match @fsx.copy_file(from, @json.join_path(pdir, file)) {
        Ok(_) => copied = copied + 1
        Err(e) => return Err(("io-error", "复制 " + file + " 失败：" + e))
      }
    }
  }
  // node_modules 只软链不复制：源 profile 自带就用它，否则用 profiles/ 下共享的提升目录
  let src_nm = @json.join_path(src_dir, "node_modules")
  let hoisted_nm = @json.join_all([dsh_home, "profiles", "node_modules"])
  let nm_target = if @json.is_dir(src_nm) {
    src_nm
  } else if @json.is_dir(hoisted_nm) {
    hoisted_nm
  } else {
    ""
  }
  if nm_target == "" {
    return Err(
      (
        "io-error",
        "源 profile 与 " + hoisted_nm + " 都没有 node_modules，没法给这份 home 摆软链",
      ),
    )
  }
  match @fsx.make_symlink(nm_target, @json.join_path(pdir, "node_modules")) {
    Ok(_) => ()
    Err(e) => return Err(("io-error", e))
  }
  let src_skills = @json.join_path(dsh_home, "skills")
  let mut skills_linked = false
  if @json.is_dir(src_skills) {
    match @fsx.make_symlink(src_skills, @json.join_path(home, "skills")) {
      Ok(_) => skills_linked = true
      Err(e) => return Err(("io-error", e))
    }
  }
  match @fsx.ensure_dir(@json.join_path(home, "logs")) {
    Ok(_) => ()
    Err(e) => return Err(("io-error", e))
  }
  // 凭证：只写路径，不碰文件本身（@json.exists 只 stat，不读内容）
  let cred = @json.join_path(dsh_home, ".credentials.yaml")
  match add_credentials_patch(@json.join_path(pdir, "cordis.patch.yml"), cred) {
    Ok(_) => ()
    Err(e) => return Err(("io-error", "写凭证路径失败：" + e))
  }
  Ok({
    files_copied: copied,
    node_modules_target: nm_target,
    skills_linked,
    credentials_path: cred,
    credentials_key: "credentials.config.path",
  })
}

///|
/// 建一只 profile 的隔离 home。已存在报 conflict（不覆盖）。
///
/// 失败一律回滚：删掉刚建的目录再报，不留半成品（规格第 3 节）。
pub async fn isolate_profile(
  name_in : String,
) -> Result[IsolateOutcome, (String, String)] noraise {
  let name = @json.trim_both(name_in)
  if !single_segment(name) {
    return Err(("bad-params", "profile 名要是单段（不含 / 与 ..，非空）：" + name))
  }
  let (root, _root_source) = homes_root()
  let (dsh_home, _dsh_home_source) = @runtime.resolve_dsh_home()
  let src_dir = @json.join_all([dsh_home, "profiles", name])
  if !@json.is_dir(src_dir) {
    return Err(("not-found", "profile 目录不存在：" + src_dir))
  }
  let home = isolated_home_dir(root, name)
  // 硬约束：目标必须正好是 <root>/<单段名字>，拼出来不是这一条就不动
  if home != root + "/" + name {
    return Err(("bad-params", "隔离 home 路径不在 " + root + " 下：" + home))
  }
  if @json.exists(home) {
    return Err(("conflict", "隔离 home 已经存在：" + home + "（不覆盖；要重建先取消隔离）"))
  }
  let layout = match layout_home(home, name, src_dir, dsh_home) {
    Err((code, message)) => return rollback(home, code, message)
    Ok(got) => got
  }
  let pdir = @json.join_all([home, "profiles", name])
  let created = @json.iso_from_epoch_ms(@async.now())
  let marker = @json.JObj([
    ("profile", @json.JStr(name)),
    ("createdAt", @json.JStr(created)),
    ("dshHome", @json.JStr(dsh_home)),
    ("homesRoot", @json.JStr(root)),
    ("credentialsPath", @json.JStr(layout.credentials_path)),
    ("credentialsKey", @json.JStr(layout.credentials_key)),
    ("nodeModulesTarget", @json.JStr(layout.node_modules_target)),
  ])
  match @fsx.write_text_atomic(
    @json.join_path(home, isolation_marker),
    @json.encode(marker) + "\n",
  ) {
    Ok(_) => ()
    Err(e) => return rollback(home, "io-error", "写隔离记录失败：" + e)
  }
  match verify_isolated(pdir, layout.node_modules_target) {
    Some(problem) => return rollback(home, "io-error", "隔离后的核对没过：" + problem)
    None => ()
  }
  Ok({
    profile: name,
    path: home,
    profile_dir: pdir,
    files_copied: layout.files_copied,
    node_modules_target: layout.node_modules_target,
    skills_linked: layout.skills_linked,
    credentials_path: layout.credentials_path,
    credentials_key: layout.credentials_key,
    created_at: Some(created),
  })
}

///|
/// 删一只 profile 的隔离 home（只删 <root>/<名字>，不碰 <DSH_HOME>）。
///
/// 前缀口径与路径核对都在这里：名字不是单段、或拼出来的不是 <root>/<单段名字>，一律拒。
/// 有实例在跑由调用方（actions）先挡 —— 这里只管磁盘。
pub async fn deisolate_profile(
  name_in : String,
) -> Result[DeisolateOutcome, (String, String)] noraise {
  let name = @json.trim_both(name_in)
  if !single_segment(name) {
    return Err(("bad-params", "profile 名要是单段（不含 / 与 ..，非空）：" + name))
  }
  let (root, root_source) = homes_root()
  let home = isolated_home_dir(root, name)
  if home != root + "/" + name {
    return Err(("bad-params", "隔离 home 路径不在 " + root + " 下：" + home))
  }
  if !@json.is_dir(home) {
    return Err(("not-found", "没有隔离 home：" + home + "（homes root 来自 " + root_source + "）"))
  }
  let (files, bytes, size_source) = match @fsx.measure_tree(home) {
    Ok((f, b)) => (Some(f), Some(b), "")
    Err(e) => (None, None, e)
  }
  match @fsx.remove_tree(home) {
    Ok(_) => ()
    Err(e) => return Err(("io-error", e))
  }
  Ok({ profile: name, path: home, files, bytes, size_source })
}


// ── 试跑用的一次性 home（design/deep-home-isolation.md 第 6 节、§9.4）────────
//
// 试跑不再借用户真实 home 里的那份 profile：这一份是临时铺出来的，
// 铺法照第 2 节（复制配置、软链 node_modules 与 skills、凭证只写路径），
// 收尾（verdict 的 good / bad、trial-stop、abort）时整份删掉。
//
// 硬约束：只建 / 只删 <homes root>/trial-<作业 id 末 6 位>；
// 删之前按前缀与路径核对，不接收客户端给的任意路径。

///|
/// 作业 id 能不能拿来拼一次性 home 的名字：只认小写字母 / 数字 / 连字符
/// （与作业文件 id 同一把尺子，见 store 的 job_id_valid），且不以连字符开头。
fn trial_job_id_ok(id : String) -> Bool {
  if id == "" || id.length() > 80 || id.has_prefix("-") {
    return false
  }
  for ch in id {
    let code = ch.to_int()
    let ok = (code >= 48 && code <= 57) ||
      (code >= 97 && code <= 122) ||
      ch == '-'
    if !ok {
      return false
    }
  }
  true
}

///|
/// 作业 id → 一次性 home 的目录名 trial-<末 6 位>（id 不足 6 位就是整段）。
pub fn trial_home_name(job_id : String) -> String? {
  let id = @json.trim_both(job_id)
  if !trial_job_id_ok(id) {
    return None
  }
  let n = id.length()
  let tail = if n <= 6 { id } else { @json.slice(id, n - 6, n) }
  Some(trial_home_prefix + tail)
}

///|
/// 一次性 home 的路径（不判断存在）。硬约束：正好是 <root>/trial-<单段>。
/// 拼出来不是这一条就给 None —— 路径不从这里以外的地方来。
pub fn trial_home_path(root : String, job_id : String) -> String? {
  match trial_home_name(job_id) {
    None => None
    Some(name) =>
      if !single_segment(name) || !name.has_prefix(trial_home_prefix) {
        None
      } else {
        Some(root + "/" + name)
      }
  }
}

///|
/// 一次建试跑 home 的结果。作业里的 trial 三格与证据都从这里取，不另猜。
pub(all) struct TrialHome {
  job_id : String
  path : String
  profile : String
  /// 复制过去的那份 profile 目录：<path>/profiles/<名字>
  profile_dir : String
  files_copied : Int
  node_modules_target : String
  skills_linked : Bool
  credentials_path : String
  credentials_key : String
  created_at : String
  /// 建之前有没有一份旧的在（上次没收干净）：有就先删掉，这句话照实写「删掉了哪一份」
  replaced : String
}

///|
/// 建之前把上次留下的那一份删掉，并把这件事实写成一句话。
/// 返回 (说明, 错误)：删不掉时错误非空，调用方不能接着建新的。
async fn clear_stale_trial_home(home : String) -> (String, String) noraise {
  if !@json.exists(home) {
    return ("", "")
  }
  let size_text = match @fsx.measure_tree(home) {
    Ok((files, bytes)) =>
      "（" + files.to_string() + " 个文件，" + bytes.to_string() + " 字节）"
    Err(_) => "（体积读不到）"
  }
  match @fsx.remove_tree(home) {
    Ok(_) => ("上次留下的 " + home + " 已经先删掉" + size_text, "")
    Err(e) =>
      (
        "",
        "上次留下的一次性 home 删不掉，不能在建新的之前留着一份旧的：" + e,
      )
  }
}

///|
/// 建一份试跑用的一次性 home：<homes root>/trial-<作业 id 末 6 位>/
///
/// 建之前先看有没有旧的那一份（上次没收干净）：有就先删再建，删了哪一份照实写进
/// replaced（调用方把它写进证据）。
/// 任何一步失败都把刚建的那份删掉再报 —— 不留半成品给下一次「先删再建」去收拾。
pub async fn create_trial_home(
  job_id_in : String,
  name_in : String,
) -> Result[TrialHome, (String, String)] noraise {
  let name = @json.trim_both(name_in)
  if !single_segment(name) {
    return Err(("bad-params", "profile 名要是单段（不含 / 与 ..，非空）：" + name))
  }
  let job_id = @json.trim_both(job_id_in)
  let (root, root_source) = homes_root()
  let home = match trial_home_path(root, job_id) {
    Some(h) => h
    None =>
      return Err(
        (
          "bad-params",
          "试跑 home 的路径拼不出来（作业 id 认不出）：" + job_id +
          "；homes root 来自 " + root_source + "：" + root,
        ),
      )
  }
  let (dsh_home, _dsh_home_source) = @runtime.resolve_dsh_home()
  let src_dir = @json.join_all([dsh_home, "profiles", name])
  if !@json.is_dir(src_dir) {
    return Err(("not-found", "profile 目录不存在：" + src_dir))
  }
  let (replaced, stale_error) = clear_stale_trial_home(home)
  if stale_error != "" {
    return Err(("io-error", stale_error))
  }
  let layout = match layout_home(home, name, src_dir, dsh_home) {
    Err((code, message)) => {
      let _ = @fsx.remove_tree(home)
      return Err((code, message + "；刚建的 " + home + " 已经删掉，没有留下半成品"))
    }
    Ok(got) => got
  }
  let pdir = @json.join_all([home, "profiles", name])
  let created = @json.iso_from_epoch_ms(@async.now())
  let marker = @json.JObj([
    ("kind", @json.JStr(home_kind_trial)),
    ("jobId", @json.JStr(job_id)),
    ("profile", @json.JStr(name)),
    ("createdAt", @json.JStr(created)),
    ("dshHome", @json.JStr(dsh_home)),
    ("homesRoot", @json.JStr(root)),
    ("profileSource", @json.JStr(src_dir)),
    ("credentialsPath", @json.JStr(layout.credentials_path)),
    ("credentialsKey", @json.JStr(layout.credentials_key)),
    ("nodeModulesTarget", @json.JStr(layout.node_modules_target)),
  ])
  let marker_write = @fsx.write_text_atomic(
    @json.join_path(home, isolation_marker),
    @json.encode(marker) + "\n",
  )
  match marker_write {
    Ok(_) => ()
    Err(e) => {
      let _ = @fsx.remove_tree(home)
      return Err(
        ("io-error", "写一次性 home 的记录失败：" + e + "；刚建的 " + home + " 已经删掉"),
      )
    }
  }
  match verify_isolated(pdir, layout.node_modules_target) {
    Some(problem) => {
      let _ = @fsx.remove_tree(home)
      return Err(
        (
          "io-error",
          "一次性 home 的核对没过：" + problem + "；刚建的 " + home + " 已经删掉",
        ),
      )
    }
    None => ()
  }
  Ok({
    job_id,
    path: home,
    profile: name,
    profile_dir: pdir,
    files_copied: layout.files_copied,
    node_modules_target: layout.node_modules_target,
    skills_linked: layout.skills_linked,
    credentials_path: layout.credentials_path,
    credentials_key: layout.credentials_key,
    created_at: created,
    replaced,
  })
}

///|
/// 删一份试跑用的一次性 home。成功给一句人话（进证据 / 正文），失败给 (错误码, 原因)。
///
/// 路径核对：必须正好是 <homes root>/trial-<单段>，且不带 . / .. —— 这一道挡的是
/// 「拿一个别的路径来让控制台删」这件事，不是格式洁癖。
pub async fn remove_trial_home(
  home_in : String,
) -> Result[String, (String, String)] noraise {
  let (root, _root_source) = homes_root()
  let home = trim_tail_slash(@json.trim_both(home_in))
  if home == "" {
    return Err(("bad-params", "没有给出要删的试跑 home 路径"))
  }
  let prefix = root + "/"
  if !home.has_prefix(prefix) {
    return Err(("bad-params", "试跑 home 不在 " + root + " 下，没有动它：" + home))
  }
  let name = @json.slice_from(home, prefix.length())
  if !single_segment(name) || !name.has_prefix(trial_home_prefix) {
    return Err(
      (
        "bad-params",
        "只删 " + root + "/" + trial_home_prefix + "… 这一种目录，没有动它：" + home,
      ),
    )
  }
  if !@json.is_dir(home) {
    return Ok("一次性 home 本来就不在：" + home)
  }
  let size_text = match @fsx.measure_tree(home) {
    Ok((files, bytes)) =>
      "（" + files.to_string() + " 个文件，" + bytes.to_string() + " 字节）"
    Err(_) => "（体积读不到）"
  }
  match @fsx.remove_tree(home) {
    Ok(_) => Ok("一次性 home 已经删掉：" + home + size_text)
    Err(e) => Err(("io-error", "一次性 home 没删掉：" + e))
  }
}

