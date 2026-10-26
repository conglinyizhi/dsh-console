// 快照去重（§16 的补充）：拍之前要能判断「profile 现在这三个文件和最近一份是否逐字节一致」。
//
// 用仓库内临时目录，跑完自己清；不依赖控制台进程。

///|
async fn cleanup_dir(dir : String) -> Unit {
  match @fsx.remove_tree_fs(dir) {
    Ok(_) => ()
    Err(_) => ()
  }
}

///|
async fn write_text(path : String, text : String) -> Unit {
  match @fsx.write_text_atomic_fs(path, text) {
    Ok(_) => ()
    Err(_) => ()
  }
}

///|
async fn make_dir(path : String) -> Unit {
  match @fsx.ensure_dir_fs(path) {
    Ok(_) => ()
    Err(_) => ()
  }
}

///|
async test "三个文件逐字节一致时判为一致" {
  let base = ".tmp-verify/snapshot-dedupe-same"
  cleanup_dir(base)
  let profile = base + "/profile"
  let snap = base + "/profile/.snapshots/1000"
  make_dir(profile)
  make_dir(snap)
  write_text(profile + "/cordis.patch.yml", "- id: a\n")
  write_text(snap + "/cordis.patch.yml", "- id: a\n")
  assert_true(same_as_snapshot(profile, snap))
  cleanup_dir(base)
}

///|
async test "任一文件改了一个字节就判为不一致" {
  let base = ".tmp-verify/snapshot-dedupe-diff"
  cleanup_dir(base)
  let profile = base + "/profile"
  let snap = base + "/profile/.snapshots/1000"
  make_dir(profile)
  make_dir(snap)
  write_text(profile + "/cordis.patch.yml", "- id: a\n")
  write_text(snap + "/cordis.patch.yml", "- id: b\n")
  assert_false(same_as_snapshot(profile, snap))
  cleanup_dir(base)
}

///|
async test "一边有一边没有也判为不一致" {
  let base = ".tmp-verify/snapshot-dedupe-missing"
  cleanup_dir(base)
  let profile = base + "/profile"
  let snap = base + "/profile/.snapshots/1000"
  make_dir(profile)
  make_dir(snap)
  write_text(profile + "/cordis.patch.yml", "- id: a\n")
  write_text(profile + "/package.json", "{}\n")
  write_text(snap + "/cordis.patch.yml", "- id: a\n")
  // profile 里有 package.json，快照里没有：不一致
  assert_false(same_as_snapshot(profile, snap))
  cleanup_dir(base)
}

///|
async test "两边都没有的文件不算差异" {
  let base = ".tmp-verify/snapshot-dedupe-none"
  cleanup_dir(base)
  let profile = base + "/profile"
  let snap = base + "/profile/.snapshots/1000"
  make_dir(profile)
  make_dir(snap)
  // 两个目录都空：三个文件一个都没有，算一致
  assert_true(same_as_snapshot(profile, snap))
  cleanup_dir(base)
}

///|
async test "最新那份取数字目录里最大的" {
  let base = ".tmp-verify/snapshot-latest"
  cleanup_dir(base)
  let dir = base + "/.snapshots"
  make_dir(dir)
  make_dir(dir + "/1000")
  make_dir(dir + "/3000")
  make_dir(dir + "/2000")
  make_dir(dir + "/not-a-number")
  match latest_snapshot_id(dir) {
    Some(id) => assert_eq(id, "3000")
    None => fail("应该取到 3000")
  }
  cleanup_dir(base)
}

///|
async test "没有快照目录时给 None" {
  let base = ".tmp-verify/snapshot-latest-empty"
  cleanup_dir(base)
  make_dir(base)
  match latest_snapshot_id(base) {
    Some(_) => fail("空目录不该有最新快照")
    None => ()
  }
  cleanup_dir(base)
}
