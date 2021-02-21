const userIdBase = 'User_'
const regionIdBase = 'Region_'
const genderFemale = 'Female'
const genderMale = 'Male'
const genderNotSpecified = 'Not Specified'
const maxUserId = 100
const maxRegionId = 1000

let interval = 1000;

function generateUserId() {
    return generateId(userIdBase, maxUserId);
}

function generateRegionId() {
    return generateId(regionIdBase, maxRegionId);
}

function generateId(idBase, maxIdValue) {
    var id = Math.floor(Math.random() * maxIdValue);
    var idString = idBase + id;
    return idString;
}

function generateGender() {
    var gender = "Not Specified";
    var genderValue = Math.random();
    if (genderValue <= 0.33) {
        gender = "Female"
    } else if (genderValue <= 0.66) {
        gender = "Male"
    }
    return gender;
}

function sleep(ms) {
    return new Promise(resolve=>{
        setTimeout(resolve,ms)
    })
}

async function begin() {
while(true) {

        // Get a user ID.
        userId = generateUserId();

        // Concatenate a delimited record of the form <key>:<value>.
        // - The record key is userId, delimited by a ':' character.
        // - The record value is a comma-delimited list of fields.
        //
        //   <userId>:<register-time>,<userId>,<regionId>,<gender>
        //
        // Example record:
        //   User_29:1567546454224,User_29,Region_923,Female

        record = userId + ":";
        record += new Date().valueOf() + ",";
        record += userId + ",";
        record += generateRegionId() + ",";
        record += generateGender();
        console.log(record);

        await sleep(interval);
    }
}
begin();
