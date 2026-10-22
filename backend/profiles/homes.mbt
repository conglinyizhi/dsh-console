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
/// 回收站里放「整份额外 home」的那一格目录名（design/deep-home-isolation.md 第 9.4 节）：
/// `<trash>/homes/<名字>-<毫秒>/`。
///
/// 与回收站里 profile 目录那一条不同：这一格装的是**一整份 home**（里面有 profiles/、
/// sessions/、logs/ 与插件写在根下的目录），不是一只 profile 的目录。所以它放在子目录里，
/// 而且回收站的列表与恢复 / 彻底删除都要把它当成「容器」跳过 —— 拿它当条目去恢复，
/// 就是把整份 home 当成一只 profile 挪进别人的 profiles/ 里。
pub let trash_homes_dir : String = "homes"

///|
/// 读数里的两档归属。
pub let home_kind_isolated : String = "isolated"

///|
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
  "cordis.yml", "cordis.patch.yml", "package.json", "pnpm-workspace.yaml",
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
        (
          fallback,
          "默认 ~/.dsh-homes（" +
          homes_root_env +
          " 不是绝对路径，按未设置处理）",
        )
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
/// 这只 profile 的目录**现在**在磁盘上的哪儿，以及它属于哪一份 home。
///
/// 真移动之后这两件事必须一起回答（以前是复制，共用那一份还在，只按 DSH_HOME 拼也对）：
///   隔离的那一只 → <root>/<名字>/profiles/<名字>（它的目录已经搬进自己的 home）
///   共用的那一只 → <DSH_HOME>/profiles/<名字>
///
/// 返回 (profile 目录, 那一份 home 的根)。名字先过 single_segment —— 拼出来的路径只可能
/// 是这两条中的一条，不会因为名字里带斜杠跑到别处。
pub async fn profile_location(name_in : String) -> (String, String) noraise {
  let name = @json.trim_both(name_in)
  if !single_segment(name) {
    // 名字不合法时给共用那一档的拼法：调用方随后一定撞上 not-found，
    // 而不是被这里领到一个**看着像真的**路径上去动手。
    let (dsh_home, _) = @runtime.resolve_dsh_home()
    return (
      @json.join_path(@json.join_path(dsh_home, "profiles"), name),
      dsh_home,
    )
  }
  match isolated_home_of(name) {
    Some(home) => (@json.join_all([home, "profiles", name]), home)
    None => {
      let (dsh_home, _) = @runtime.resolve_dsh_home()
      (@json.join_all([dsh_home, "profiles", name]), dsh_home)
    }
  }
}

///|
/// homes root 下现在有哪些名字是真的隔离 home（<root>/<名字>/profiles/<名字> 是目录）。
///
/// 名册只从磁盘读，不从任何记录里猜：试跑的一次性 home（trial- 前缀）不算 ——
/// 那不是任何一只 profile 的家。真移动之后，总览要靠这一份名册才看得见隔离的那几只
/// （它们的目录已经不在 <DSH_HOME>/profiles 下了）。
pub async fn isolated_profile_names() -> Array[String] noraise {
  let (root, _) = homes_root()
  let out : Array[String] = []
  if !@json.is_dir(root) {
    return out
  }
  for entry in @json.list_entries(root) {
    let (name, is_dir) = entry
    if !is_dir || !single_segment(name) || name.has_prefix(trial_home_prefix) {
      continue
    }
    if @json.is_dir(@json.join_all([root, name, "profiles", name])) {
      out.push(name)
    }
  }
  out
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
  match @json.read_text_file_fs(path) {
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
            "；createdAt 取 " +
            home +
            " 目录的 mtime（没有隔离记录文件）",
          )
        None =>
          (
            None,
            "；createdAt 读不到（没有隔离记录文件，" +
            home +
            " 也读不到 mtime）",
          )
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
      source: "隔离 home 在：" +
      pdir +
      "（homes root 来自 " +
      root_source +
      "：" +
      root +
      "）" +
      created_source,
    }
  } else {
    {
      kind: home_kind_shared,
      path: dsh_home,
      profile_dir: @json.join_all([dsh_home, "profiles", name]),
      created_at: None,
      source: "没有隔离 home（" +
      pdir +
      " 不存在），用控制台的 home " +
      dsh_home +
      "（" +
      dsh_home_source +
      "）；createdAt 只在隔离 home 里有意义",
    }
  }
}

///|
/// 移动一个目录（rename：同一文件系统上只改目录项，与体积无关）。
async fn move_dir(
  from : String,
  to : String,
) -> Result[Unit, (String, String)] noraise {
  match @fsx.rename_path(from, to) {
    Ok(_) => Ok(())
    Err(e) => Err(("io-error", "移动没完成：" + e))
  }
}

///|
/// 移动前的前件之一：两边在不在同一个文件系统（规格 9.2 第 1 条）。
///
/// 设备号不同就停手：跨盘 rename 会给 EXDEV，退化成「复制再删」之后体积一大就不再是
/// 瞬时的，而使用者要的是「移动」这件事本身。成功时把实测的设备号写进那句话（进悬停）。
async fn require_same_device(
  a : String,
  b : String,
) -> Result[String, (String, String)] noraise {
  let dev_a = match @fsx.dev_of(a) {
    Ok(d) => d
    Err(e) => return Err(("io-error", e))
  }
  let dev_b = match @fsx.dev_of(b) {
    Ok(d) => d
    Err(e) => return Err(("io-error", e))
  }
  if dev_a != dev_b {
    return Err(
      (
        "io-error",
        "两边不在同一个文件系统，移动会退化成复制：把 homes root 放到与 DSH_HOME 同一个盘上再试" +
        "（" +
        a +
        " 的设备号 " +
        dev_a.to_string() +
        "，" +
        b +
        " 的设备号 " +
        dev_b.to_string() +
        "）",
      ),
    )
  }
  Ok(
    "两边同一个文件系统（设备号 " +
    dev_a.to_string() +
    "）：" +
    a +
    " 与 " +
    b,
  )
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
/// 一份 profile 目录里的 node_modules 指向哪儿：软链就给目标，真实目录或没有就给空串。
/// 只用于回执里那句证据，不参与判断（判断在 verify_isolated）。
fn node_modules_target_of(pdir : String) -> String {
  let link = @json.join_path(pdir, "node_modules")
  match @json.read_link_fs(link) {
    Ok(target) => target
    Err(_) => ""
  }
}

///|
/// 一份 profile 目录的核对（复制完 / 移动完都用这一套）：目录在、package.json 读得出、
/// node_modules **如果有**就指得通、cordis.patch.yml 在。任何一条不过给 Some(原因)，
/// 调用方据此回滚或移回原处。
///
/// nm_target 非空时还要比对软链目标（复制那条路知道自己摆的是哪一条）；
/// 移动那条路传空串 —— 移过来的 node_modules 是这一份自己带着的，比对的对象不存在，
/// 只核对「指得通」。移动不新摆软链，所以真实目录也算过（规格 9.2 第 4 条只在有它时要求）。
async fn verify_isolated(pdir : String, nm_target : String) -> String? noraise {
  if !@json.is_dir(pdir) {
    return Some("profile 目录不在：" + pdir)
  }
  let pkg = @json.join_path(pdir, "package.json")
  match @json.read_text_file_fs(pkg) {
    Err(e) => {
      @store.note_raw(e.raw)
      return Some("package.json 读不出来：" + pkg)
    }
    Ok(text) =>
      match @json.json_parse(text) {
        Some(_) => ()
        None => return Some("package.json 不是合法 JSON：" + pkg)
      }
  }
  let link = @json.join_path(pdir, "node_modules")
  let kind = @fs.kind(link, follow_symlink=false) catch { _ => Unknown }
  match kind {
    Directory => ()
    SymLink => {
      let target = match @json.read_link_fs(link) {
        Err(e) => {
          @store.note_raw(e.raw)
          return Some("node_modules 软链读不出目标：" + link)
        }
        Ok(target) => target
      }
      if !@json.is_dir(link) {
        return Some(
          "node_modules 软链指不到目录：" + link + " -> " + target,
        )
      }
      if nm_target != "" && target != nm_target {
        return Some(
          "node_modules 软链指向 " + target + "，不是 " + nm_target,
        )
      }
    }
    Regular =>
      return Some(
        "node_modules 是个普通文件：" +
        link +
        "（既不是目录也不是软链）",
      )
    _ => ()
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
  files_copied : Int32
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
  match @fsx.ensure_dir_fs(pdir) {
    Ok(_) => ()
    Err(e) => {
      @store.note_raw(e.raw)
      return Err(("io-error", "建软链失败"))
    }
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
        "源 profile 与 " +
        hoisted_nm +
        " 都没有 node_modules，没法给这份 home 摆软链",
      ),
    )
  }
  match @fsx.make_symlink_fs(nm_target, @json.join_path(pdir, "node_modules")) {
    Ok(_) => ()
    Err(e) => {
      @store.note_raw(e.raw)
      return Err(("io-error", "建软链失败"))
    }
  }
  let src_skills = @json.join_path(dsh_home, "skills")
  let mut skills_linked = false
  if @json.is_dir(src_skills) {
    match @fsx.make_symlink_fs(src_skills, @json.join_path(home, "skills")) {
      Ok(_) => skills_linked = true
      Err(e) => {
        @store.note_raw(e.raw)
        return Err(("io-error", "建软链失败"))
    }
    }
  }
  match @fsx.ensure_dir_fs(@json.join_path(home, "logs")) {
    Ok(_) => ()
    Err(e) => {
      @store.note_raw(e.raw)
      return Err(("io-error", "写文件失败"))
    }
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