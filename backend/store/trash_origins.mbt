// 回收站条目的来源 home：trash-origins.json —— { "<trash 下的目录名>": "<home>" }。
//
// 为什么要有这一份：回收站目录名是 `<profile>-<epochMs>`，里面**没有 home**；
// 而恢复必须回到它来的那个 home —— 同名两份档案在两个 home 里时，「回哪个 home」
// 只能靠删的那一刻记下来，事后从目录名里推不出来（推得出来就是猜）。
//
// 为什么不在条目目录里放一个标记文件：那个目录本身就是那只 profile 的目录，
// 恢复时会连里面的东西一起搬回去 —— 往里写一个标记，等于给恢复回去的 profile
// 添了一个它自己没写过的文件；顺带那份文件还会被算进「几个文件 · 多少字节」的读数里。
// 按目录名查这一份表，条目本身一个字节都不动 ✓
//
// 键用的是**目录名**（不是完整路径）：list_trash 先列 trash/ 下有什么，再拿目录名来查；
// 查不到的按「没记下来源」处理 —— 那是本次改动之前删的旧条目，恢复时落回控制台自己的 home，
// 并把这件事如实说出来（见 trash.mbt 的 restore_from_trash）。
//
// 写是原子写；读不动 / 坏的项一律跳过并把原因写进 note（读侧绝不编一个 home 出来）。

///|
/// 读出来的来源表 + 文件级问题。
pub struct LoadedTrashOrigins {
  /// 目录名 -> 来源 home（已归一化的绝对路径）
  origins : Map[String, String]
  note : String?
}

///|
/// 读来源表。文件不存在 -> 空表（全新环境不是错误）；坏了 -> 空表 + note。
pub async fn load_trash_origins() -> LoadedTrashOrigins noraise {
  let paths = state_paths()
  let (file, file_error) = read_state_json(paths.trash_origins)
  let origins : Map[String, String] = Map([])
  let mut note = file_error
  match file {
    None => ()
    Some(json) =>
      match json {
        Object(_) => {
          let mut dropped = 0
          for pair in object_entries(json) {
            let (dir, value) = pair
            match as_string(value) {
              Some(home) =>
                match normalize_home(home) {
                  // 认下来的 home 一律存归一化后的那一份：id / 键这类东西最怕等价写法两种
                  Some(normalized) => origins[dir] = normalized
                  None => dropped = dropped + 1
                }
              None => dropped = dropped + 1
            }
          }
          if dropped > 0 {
            note = Some(
              "trash-origins.json 里有 " +
              dropped.to_string() +
              " 条认不出来的来源 home，已跳过（那几条恢复时落回控制台自己的 home）",
            )
          }
        }
        _ =>
          note = Some(
            "trash-origins.json 顶层不是对象，按空表处理：" +
            paths.trash_origins,
          )
      }
  }
  { origins, note, }
}

///|
/// 整表落盘（原子写）。失败原样回原因：这一步失败意味着「这一条回收站条目记不住从哪来的」，
/// 调用方要把这件事说出来，不能吞掉 —— 吞掉的表现就是删隔离那份、恢复却落到主线上。
pub async fn save_trash_origins(
  origins : Map[String, String],
) -> Result[Unit, String] noraise {
  let paths = state_paths()
  let fields : Array[(String, @json.JsonVal)] = []
  for dir, home in origins {
    fields.push((dir, @json.JStr(home)))
  }
  match @fsx.write_text_atomic_fs(
    paths.trash_origins,
    @json.encode(@json.JObj(fields)) + "\n",
  ) {
    Ok(_) => Ok(())
    Err(e) => {
      note_raw(e.raw)
      Err("写文件失败")
    }
  }
}

///|
/// 记一条：这个回收站目录是从 home 删的。
///
/// home 认不出来（不是绝对路径之类）直接报错、不落盘：宁可不记，也不记一个假的来源 ——
/// 假的来源会让「恢复到哪里」这一步去动一个不该动的目录。
pub async fn put_trash_origin(
  dir : String,
  home : String,
) -> Result[Unit, String] noraise {
  let normalized = match normalize_home(home) {
    Some(v) => v
    None =>
      return Err(
        "来源 home 认不出来（要绝对路径、不含 . 与 .. 段）：" +
        home,
      )
  }
  let loaded = load_trash_origins()
  let origins = loaded.origins
  origins[dir] = normalized
  save_trash_origins(origins)
}

///|
/// 忘掉一条：这一条已经不在了（恢复走了 / 彻底删了）。查不到也算成功 —— 这一步是幂等的。
///
/// 表里留下一条指向已不存在的目录的记录不会误导谁（查表的人只查列出来的目录名），
/// 所以这一步失败不算致命：调用方把原因如实带出去就行。
pub async fn drop_trash_origin(dir : String) -> Result[Unit, String] noraise {
  let loaded = load_trash_origins()
  let next : Map[String, String] = Map([])
  for name, home in loaded.origins {
    if name != dir {
      next[name] = home
    }
  }
  save_trash_origins(next)
}
