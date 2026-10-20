// 搬家之后重算相对软链接与配置里的旧目录前缀（design/design-fixes.md §48）。
//
// 为什么必须重算：相对软链接是按「链接自己所在目录」解析的。profile 从
// <DSH_HOME>/profiles/<名> 搬到 <homes root>/<名>/profiles/<名>（多两层）之后，
// 同一段 ../../../../../x 就指到别处去，插件的 @local 链接于是全变成「包不可用」。
// isolate / deisolate 只搬文件、fork 只拷文件，都不碰链接文本 —— 这一层补上。
//
// 口径（§48.1）：只处理 profile 目录里的符号链接（含 node_modules 下）；
//   · 相对链接：用「旧链接所在目录 + 链接文本」算出它原本指向的绝对目标，
//     再用「新链接所在目录」重算相对路径写回；
//   · 目标不存在就跳过并记一条（原本就是坏的，不猜）；
//   · 绝对链接原样保留（它们不随目录变）。
//
// 配置文件（§48.2）：cordis.patch.yml 与 package.json 里以旧 profile 目录开头的绝对路径
// 换成本次搬家的新前缀，替换条数进审计 outcome 的 refsRewritten。

///|
/// 一次 relink 的结果。四个数都进回执 / 审计（§48.2 要的 refsRewritten 是其中之一）。
pub(all) struct RelinkReport {
  /// 重写过的相对链接条数
  mut links_fixed : Int
  /// 跳过的链接条数：目标找不到（原本就坏）、或链接本身读不出来
  mut links_broken : Int
  /// cordis.patch.yml / package.json 里换掉的前缀条数
  mut refs_rewritten : Int
  /// 跳过的那几条各自的原文（进悬停，最多留 5 条）
  mut notes : Array[String]
}

///|
/// 一个空结果（没有要改的东西时用）。
fn empty_report() -> RelinkReport {
  { links_fixed: 0, links_broken: 0, refs_rewritten: 0, notes: [] }
}

///|
/// 这条路径是不是绝对路径（Windows 的盘符写法也认）。
fn path_is_absolute(path : String) -> Bool {
  if path.length() == 0 {
    return false
  }
  if path[0] == '/' {
    return true
  }
  // Windows 盘符写法（C:… / C:/…）：第二个字符是冒号就算绝对
  path.length() > 1 && path[1] == ':' && (path.length() > 2 && (path[2] == '/' || path[2] == '\\'))
}

///|
/// 把路径拆成段（丢掉空段与 .，.. 就地消掉一层）。只做字面归一，不查磁盘。
fn path_segments(path : String) -> Array[String] {
  let out : Array[String] = []
  for part in path.split("/") {
    let seg = @json.owned(part)
    if seg == "" || seg == "." {
      continue
    }
    if seg == ".." {
      if out.length() > 0 && out[out.length() - 1] != ".." {
        let _ = out.pop()
      } else {
        out.push(seg)
      }
      continue
    }
    out.push(seg)
  }
  out
}

///|
/// 字面归一一条绝对路径：`a/./b/../c` → `a/c`。
fn normalize_path(path : String) -> String {
  let segs = path_segments(path)
  "/" + segs.join("/")
}

///|
/// 从 from_dir 到 target（都用绝对路径）的相对路径：`../../../x/y`。
fn relative_path(from_dir : String, target : String) -> String {
  let a = path_segments(from_dir)
  let b = path_segments(target)
  let mut i = 0
  while i < a.length() && i < b.length() && a[i] == b[i] {
    i = i + 1
  }
  let out : Array[String] = []
  let mut up = i
  while up < a.length() {
    out.push("..")
    up = up + 1
  }
  let mut down = i
  while down < b.length() {
    out.push(b[down])
    down = down + 1
  }
  if out.length() == 0 {
    "."
  } else {
    out.join("/")
  }
}

///|
/// 走一遍 root，把所有符号链接列出来（不跟随链接，避免绕圈）。
///
/// 跳过 skip 里的名字（fork 时 node_modules 本来就不拷），并跳过 node_modules/.pnpm：
/// 那里是 pnpm 自己的链接农场，几千条链接既不归这份 profile 管，搬完 pnpm 也会重新链。
/// 条数有上限（避免一份超大目录把一次动作拖死）。
pub async fn collect_links(root : String, skip : Array[String]) -> Array[String] noraise {
  let out : Array[String] = []
  let queue : Array[String] = [root]
  let mut cursor = 0
  let mut visited = 0
  let max_entries = 20000
  let max_links = 2000
  while cursor < queue.length() && out.length() < max_links && visited < max_entries {
    let dir = queue[cursor]
    cursor = cursor + 1
    let names = match @json.list_dir_result(dir) {
      Ok(list) => list
      Err(_) => continue
    }
    for name in names {
      visited = visited + 1
      if visited >= max_entries {
        break
      }
      if skip.contains(name) {
        continue
      }
      if name == ".pnpm" {
        continue
      }
      let path = @json.join_path(dir, name)
      let kind = try {
        @fs.kind(path, follow_symlink=false)
      } catch {
        _ => Unknown
      }
      match kind {
        SymLink => out.push(path)
        Directory => queue.push(path)
        _ => ()
      }
    }
  }
  out
}

///|
/// 一条链接的绝对目标：(ok, 目标)。相对链接按「链接自己所在目录」解析；坏链接给 None。
fn link_target(link : String) -> String? noraise {
  let text = match @json.read_link(link) {
    Ok(t) => t
    Err(_) => return None
  }
  if path_is_absolute(text) {
    return Some(normalize_path(text))
  }
  Some(normalize_path(@json.dirname(link) + "/" + text))
}

///|
/// 把一条链接重写成指向 target 的相对路径（目标不存在时不写）。
async fn rewrite_link(link : String, target : String) -> Bool noraise {
  let new_text = relative_path(@json.dirname(link), target)
  let old_text = match @json.read_link(link) {
    Ok(t) => t
    Err(_) => ""
  }
  if old_text == new_text {
    return false
  }
  match @fsx.remove_file(link) {
    Ok(_) => ()
    Err(_) => return false
  }
  match @fsx.make_symlink(new_text, link) {
    Ok(_) => true
    Err(_) => false
  }
}

///|
/// 搬家之后跑一遍：把 new_dir 里的相对链接按 old_dir→new_dir 重算，
/// 再把两份配置里以 old_dir 开头的绝对路径换成 new_dir。
pub async fn relink_after_move(old_dir : String, new_dir : String) -> RelinkReport noraise {
  if old_dir == "" || new_dir == "" || old_dir == new_dir {
    return empty_report()
  }
  let report = empty_report()
  for link in collect_links(new_dir, []) {
    let suffix = @json.slice_from(link, new_dir.length())
    let old_link = old_dir + suffix
    let text = match @json.read_link(link) {
      Ok(t) => t
      Err(_) => {
        report.links_broken = report.links_broken + 1
        continue
      }
    }
    // 绝对链接不随目录变：原样保留（§48.1）
    if path_is_absolute(text) {
      continue
    }
    let target = normalize_path(@json.dirname(old_link) + "/" + text)
    if !@json.exists(target) {
      // 原本就是坏的：不猜一个目标出来，跳过并记一条（§48.1 / 验收 4）
      report.links_broken = report.links_broken + 1
      if report.notes.length() < 5 {
        report.notes.push(link + " -> " + text + "（目标不在：" + target + "）")
      }
      continue
    }
    if rewrite_link(link, target) {
      report.links_fixed = report.links_fixed + 1
    }
  }
  report.refs_rewritten = rewrite_refs(new_dir, old_dir, new_dir)
  report
}

///|
/// fork 用：源目录里的链接在 copy_tree 里被跳过（它只复制普通文件与目录），
/// 这一趟按「源目录解析出的绝对目标」在目标目录里重新摆一条（相对路径按目标位置算）。
pub async fn carry_symlinks(
  from : String,
  to : String,
  skip : Array[String],
) -> RelinkReport noraise {
  let report = empty_report()
  if from == "" || to == "" {
    return report
  }
  for link in collect_links(from, skip) {
    let suffix = @json.slice_from(link, from.length())
    let dst_link = to + suffix
    let text = match @json.read_link(link) {
      Ok(t) => t
      Err(_) => {
        report.links_broken = report.links_broken + 1
        continue
      }
    }
    let target = link_target(link)
    let resolved = match target {
      Some(t) => t
      None => {
        report.links_broken = report.links_broken + 1
        continue
      }
    }
    if !@json.exists(resolved) {
      report.links_broken = report.links_broken + 1
      if report.notes.length() < 5 {
        report.notes.push(link + " -> " + text + "（目标不在：" + resolved + "）")
      }
      continue
    }
    let parent = @json.dirname(dst_link)
    match @fsx.ensure_dir(parent) {
      Ok(_) => ()
      Err(_) => {
        report.links_broken = report.links_broken + 1
        continue
      }
    }
    if @json.exists(dst_link) {
      let _ = @fsx.remove_file(dst_link)
    }
    // 绝对链接照抄（它不随目录变）；相对链接按目标位置重算
    let new_text = if path_is_absolute(text) {
      text
    } else {
      relative_path(@json.dirname(dst_link), resolved)
    }
    match @fsx.make_symlink(new_text, dst_link) {
      Ok(_) => report.links_fixed = report.links_fixed + 1
      Err(_) => report.links_broken = report.links_broken + 1
    }
  }
  // 拷过来的配置文本里还写着源目录的绝对路径（§48.2）：换成本次的目标目录
  report.refs_rewritten = rewrite_refs(to, from, to)
  report
}

///|
/// 把新目录里两份配置文本中的旧目录前缀换掉，返回换了几处。
///
/// 只换「后面跟 /」或「正好等于旧目录」的出现：别把别的路径里偶然相同的片段换掉。
async fn rewrite_refs(dir : String, old_prefix : String, new_prefix : String) -> Int noraise {
  let mut total = 0
  for name in ["cordis.patch.yml", "package.json"] {
    let path = @json.join_path(dir, name)
    let text = match @json.read_text_file(path) {
      Ok(t) => t
      Err(_) => continue
    }
    let (next, count) = replace_path_prefix(text, old_prefix, new_prefix)
    if count > 0 {
      let _ = @fsx.write_text_atomic(path, next)
      total = total + count
    }
  }
  total
}

///|
/// 文本里的旧前缀替换（见 rewrite_refs 的边界口径），返回 (新文本, 条数)。
fn replace_path_prefix(text : String, from : String, to : String) -> (String, Int) {
  if from == "" || from == to {
    return (text, 0)
  }
  let out = StringBuilder()
  let chars : Array[Char] = []
  for c in text {
    chars.push(c)
  }
  let fchars : Array[Char] = []
  for c in from {
    fchars.push(c)
  }
  let n = chars.length()
  let flen = fchars.length()
  let mut i = 0
  let mut count = 0
  while i < n {
    let mut hit = i + flen <= n
    if hit {
      let mut k = 0
      while k < flen {
        if chars[i + k] != fchars[k] {
          hit = false
          break
        }
        k = k + 1
      }
    }
    // 边界：旧前缀后面必须是开头 / / / 空白 / 引号 / 行尾之一，
    // 否则说明它只是某个更长路径里的一段，不该动
    if hit && i + flen < n {
      let after = chars[i + flen]
      if after != '/' && after != ' ' && after != '"' && after != '\n' &&
        after != '\t' && after != '\r' && after != ',' {
        hit = false
      }
    }
    if hit {
      out.write_string(to)
      count = count + 1
      i = i + flen
      continue
    }
    out.write_char(chars[i])
    i = i + 1
  }
  (out.to_string(), count)
}
