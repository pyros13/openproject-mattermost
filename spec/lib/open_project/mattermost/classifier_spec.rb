  it "on a later comment folded into the same journal, threads only the new notes" do
    j = journal(
      details: {
        "project" => [nil, 14],
        "author" => [nil, 3],
        "status_id" => [nil, 1],
        "subject" => [nil, "Test OP New"]
      },
      notes: "Some Comments<br>",
      initial: true,
      user: OpenStruct.new(name: "Maya Chen")
    )
    snapshot = {
      notes: "",
      details: {
        "project" => [nil, 14],
        "author" => [nil, 3],
        "status_id" => [nil, 1],
        "subject" => [nil, "Test OP New"]
      }
    }
    result = classifier.call(j, snapshot: snapshot)
    expect(result.opened?).to eq(false)
    expect(result.bump?).to eq(false)
    expect(result.thread?).to eq(true)
    expect(result.notes).to eq("Some Comments")
    expect(result.thread_details).to be_empty
  end

  it "on a status change folded into the same journal, bumps and threads the named status" do
    j = journal(
      details: { "status_id" => [nil, 2], "subject" => [nil, "Test OP New"] },
      initial: true
    )
    snapshot = {
      notes: "",
      details: { "status_id" => [nil, 1], "subject" => [nil, "Test OP New"] }
    }
    result = classifier.call(j, snapshot: snapshot)
    expect(result.opened?).to eq(false)
    expect(result.bump?).to eq(true)
    expect(result.thread_details["status_id"]).to eq([1, 2])
  end

  it "skips an unchanged snapshot of the same journal" do
    details = { "status_id" => [nil, 1], "subject" => [nil, "Test"] }
    j = journal(details: details, notes: "", initial: true)
    result = classifier.call(j, snapshot: { notes: "", details: details })
    expect(result.opened?).to eq(false)
    expect(result.bump?).to eq(false)
    expect(result.thread?).to eq(false)
  end