// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;

// Smart contract representing a FL task
contract FLTask {
    // Representing the status of the task
    // Pending: invalid status, created when the smart contract is deployed
    // Initialized: the task is ready to be joined by workers
    // Running, Completed, Canceled: self-explanatory
    enum TaskStatus {
        Pending,
        Initialized,
        Running,
        Completed,
        Canceled
    }

    //Struct representing a wokrer of the task, still under development
    //the boolean field is used to verify that a worker cannot join the task twice
    struct Worker {
        bool registered;
        uint8 workerId;
    }


    struct WorkerOrCommitteeScore {
        address workerAddress;
        uint16 score;
        uint16 bid;
    }

    //struct representing the evaluation submitted by a worker at the end of the evaluation phase
    struct SubmittedEval {
        address workerAddress;
        address[] addressScored;
        uint16[] scores;
        //uint16 score; //only for testing
    }


    uint8 private numRounds; //number of rounds of the fl task
    uint8 private round; //number of the actual round
    uint8 private numWorkers = 0;
    uint8 public k; // top k workers
    mapping(address => Worker) private workers; //to each worker address is associated his worker object
    SubmittedEval[] private roundScores; //to each round are associated the submitted evaluations
//    address[] private roundTopK;
    address public immutable requester;
    WorkerOrCommitteeScore[] public workerScores;
    WorkerOrCommitteeScore[] public committeeScores;
    string private modelURI; //URI of the model pushed by the requester at initialization phase
    uint256 roundMoney;
    TaskStatus public taskStatus;

    constructor() {
        requester = msg.sender;
        taskStatus = TaskStatus.Pending;
    }

    // function modifier allowing the function to be called only by the requester
    modifier onlyRequester() {
        require(msg.sender == requester, "This operation can be performed only by the task requester");
        _;
    }

    // function modifier allowing the function to be called only by the workers
    modifier onlyWorker() {
        require(workers[msg.sender].registered, "This operation can be performed only by the task workers");
        _;
    }

    // function modifier allowing the function to be called only by requester and workers
    modifier restrictAccess() {
        require((workers[msg.sender].registered || msg.sender == requester), "You do not have the rights to perform this operation");
        _;
    }

    // function modifier allowing the function to be called only if the task has been initialized
    modifier taskInitialized(){
        require(uint(taskStatus) == 1, "Task not initialized");
        _;
    }

    // function modifier allowing the function to be called only if the task has started
    modifier taskRunning(){
        require(uint(taskStatus) == 2, "Task not running");
        _;
    }

    event WorkerTransferred(address worker, uint256 amount);
    event CommitteeTransferred(address committee, uint256 amount);

    // function called to initialize the task, mandatory to put a deposit in the smart contract
    function initializeTask(string memory _modelURI, uint8 _numRounds, uint8 _k) public payable onlyRequester {
        require(msg.value != 0, "Cannot initialize contract without deposit");
        modelURI = _modelURI;
        numRounds = _numRounds;
        roundMoney = msg.value / numRounds;
        taskStatus = TaskStatus.Initialized;
        k = _k;
    }

    // start the task
    function startTask() public onlyRequester {
        taskStatus = TaskStatus.Running;
        round = 1;
    }

    // advance round
    function nextRound() public onlyRequester taskRunning {
        delete roundScores;
        delete workerScores;
        delete committeeScores;
        round++;
    }

    // get the number of actual round
    function getRound() public taskRunning view returns (uint8){
        return round;
    }

    // get the number of workers
    function getNumWorkers() public view returns (uint8){
        return numWorkers;
    }

    // get the amount of money deposited in the smart contract
    function getDeposit() public onlyRequester view returns (uint) {
        return address(this).balance;
    }

    // get the address of the requester
    function getRequester() public view returns (address){
        return requester;
    }

    // get the URI of the model
    function getModelURI() public view restrictAccess returns (string memory){
        return modelURI;
    }

    function joinTask() public taskInitialized returns (string memory) {
        require(!workers[msg.sender].registered, "Worker is already registered");
        require(msg.sender != requester, "Requester cannot be a worker!");
        Worker memory worker;
        worker.registered = true;
        worker.workerId = numWorkers + 1;
        workers[msg.sender] = worker;
        numWorkers++;
        return modelURI;
    }

    function removeWorker() public {
        delete workers[msg.sender];
        numWorkers--;
    }

    function submitScore(address[] memory _workers, uint16[] memory _scores) public onlyWorker taskRunning {
        roundScores.push(SubmittedEval({
            workerAddress: msg.sender,
            addressScored: _workers,
            scores: _scores
        }));
    }

    function getSubmissionsNumber() public onlyRequester view returns (uint8){
        return uint8(roundScores.length);
    }

    function getSubmissions() public onlyRequester taskRunning view returns (SubmittedEval[] memory) {
        SubmittedEval[] memory evals = new SubmittedEval[](getSubmissionsNumber());
        for (uint8 i = 0; i < roundScores.length; i++) {
            evals[i] = roundScores[i];
        }
        return evals;
    }

    function verifyHash(bytes32 hash) public view returns (bool) {
        return hash == keccak256(abi.encodePacked(round));
    }

    function getWorkerScores() public view returns (WorkerOrCommitteeScore[] memory){
        return workerScores;
    }

    function getCommitteeScores() public view returns (WorkerOrCommitteeScore[] memory){
        return committeeScores;
    }


    function reverseAuction(WorkerOrCommitteeScore[] memory workerAndCommitteeScores) public onlyRequester {
        // compute workerScores and committeeScores
        // if round is less than numRounds / 2, then workerScores is equal to k's number of the lowest scores of all the WorkerOrCommitteeScore inside workerAndCommitteeScores, the rest is committeeScores
        // if round is bigger or equal to numRounds /2 , then workerScores is equal to k's number of the biggest scores of all the WorkerOrCommitteeScore inside workerAndCommitteeScores, the rest is committeeScores
        if (round <= numRounds / 2) {
            // sort workerAndCommitteeScores bid in ascending order
            for (uint8 i = 0; i < workerAndCommitteeScores.length - 1; i++) {
                for (uint8 j = 0; j < workerAndCommitteeScores.length - i -1; j++) {
                    if (workerAndCommitteeScores[j].bid > workerAndCommitteeScores[j + 1].bid) {
                        WorkerOrCommitteeScore memory temp = workerAndCommitteeScores[j];
                        workerAndCommitteeScores[j] = workerAndCommitteeScores[j + 1];
                        workerAndCommitteeScores[j + 1] = temp;
                    }
                }
            }
            // get the k lowest bid
            for (uint8 i = 0; i < k; i++) {
                workerScores.push(workerAndCommitteeScores[i]);
            }
            // get the rest of the bid
            for (uint8 i = k; i < workerAndCommitteeScores.length; i++) {
                committeeScores.push(workerAndCommitteeScores[i]);
            }
        } else {
            // sort workerAndCommitteeScores score in descending order
            for (uint8 i = 0; i < workerAndCommitteeScores.length - 1; i++) {
                for (uint8 j = 0; j < workerAndCommitteeScores.length - i - 1; j++) {
                    if (workerAndCommitteeScores[j].score < workerAndCommitteeScores[j + 1].score) {
                        WorkerOrCommitteeScore memory temp = workerAndCommitteeScores[j];
                        workerAndCommitteeScores[j] = workerAndCommitteeScores[j + 1];
                        workerAndCommitteeScores[j + 1] = temp;
                    }
                }
            }
            // get the k highest price
            for (uint8 i = 0; i < k; i++) {
                workerScores.push(workerAndCommitteeScores[i]);
            }
            // get the rest
            for (uint8 i = k; i < workerAndCommitteeScores.length; i++) {
                committeeScores.push(workerAndCommitteeScores[i]);
            }
        }
    }


    function distributeRewards() public onlyRequester payable {
        require(workerScores.length > 0, "No worker scores submitted yet");
        require(committeeScores.length > 0, "No committee scores submitted yet");
        // workerScores 这个数组存储的是每个worker的得分和他的地址
        // committeeScores 这个数组存储的是每个committee的得分和他的地址
        // workersToDistribute = 80% of roundMoney 这是80%的资金
        uint256 workersToDistribute = roundMoney * 8 / 10;
        // committeeToDistribute = 20% of roundMoney 这是20%的资金
        uint256 committeeToDistribute = roundMoney * 2 / 10;
        // for every worker of workerScores, they will get the money depends on their score ratio of all scores of all workerScores scores
        uint16 totalScore = 0;
        for (uint8 i = 0; i < workerScores.length; i++) {
            totalScore += workerScores[i].score;
        }
        for (uint8 i = 0; i < workerScores.length; i++) {
            // workerScores[i].score is the score of the worker
            // workerScores[i].score / totalScore is the ratio of the worker
            // workersToDistribute * workerScores[i].score / totalScore is the money of the worker
            payable(workerScores[i].workerAddress).transfer(workersToDistribute * workerScores[i].score / totalScore);
            emit WorkerTransferred(workerScores[i].workerAddress, workersToDistribute * workerScores[i].score / totalScore);
        }

        // for committee, they will get the money of committeeToDistribute equally
        uint8 committeeNumber = uint8(committeeScores.length);
        for (uint8 i = 0; i < committeeNumber; i++) {
            payable(committeeScores[i].workerAddress).transfer(committeeToDistribute / committeeNumber);
            emit CommitteeTransferred(committeeScores[i].workerAddress, committeeToDistribute / committeeNumber);
        }
    }
}
