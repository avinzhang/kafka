const userIdBase = 'User_'
const pageIdBase = 'Page_'
const maxUserId = 100
const maxPageId = 1000
const interval = 1000;

function generateUserId() {
    return generateId(userIdBase, maxUserId);
}

function generatePageId() {
    return generateId(pageIdBase, maxPageId);
}

function generateId(idBase, maxIdValue) {
    var id = Math.floor(Math.random() * maxIdValue);
    var idString = idBase + id;
    return idString;
}

function sleep(ms) {
  return new Promise(resolve=>{
      setTimeout(resolve,ms)
  })
}

const json = {};

async function begin() {
  while(true) {

    // Get a user ID.
    userId = generateUserId();

    // Concatenate a delimited record of the form <key>:<value>.
    // - The record key is userId, delimited by a ':' character.
    // - The record value is a comma-delimited list of fields.
    //
    //   <userId>:<view-time>,<userId>,<pageId>
    //
    // Example record:
    //   User_77:1567552403986,User_77,Page_132

    record = userId + ":";
    record += new Date().valueOf()  + ",";
    record += userId + ",";
    record += generatePageId();
    console.log(record);

    await sleep(interval);
  }
}
begin();
