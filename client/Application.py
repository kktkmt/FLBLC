from BCCommunicator import BCCommunicator
from FSCommunicator import FSCommunicator
from Model import Model
import torch
import os
from Requester import Requester
from Worker import Worker
from dotenv import load_dotenv
from web3 import Web3

# Main class to simulate the distributed application
class Application:
    bid_list = [2, 3, 1]

    def __init__(self, num_workers, num_rounds, fspath, num_evil=0, k=1):
        self.num_workers = num_workers
        self.num_rounds = num_rounds
        self.DEVICE = torch.device("cuda:0" if torch.cuda.is_available() else "cpu")
        self.fspath = fspath
        self.workers = []
        self.topk = num_workers
        self.worker_dict = {}
        self.worker_bid_dict = {}
        self.num_evil = num_evil
        self.k = k

    def run(self):
        load_dotenv()
        self.requester = Requester(os.getenv('REQUESTER_KEY'))
        self.requester.deploy_contract()
        self.requester.init_task(10000000000000000000, self.fspath, self.num_rounds, self.k)
        print("Task initialized")

        # in the beginning, all have the same model
        # the optimizer stays the same over all round
        # initialize all workers sequentially
        # in a real application, each device would run one worker class
        for i in range(self.num_workers):
            self.workers.append(
                Worker(self.fspath, self.DEVICE, self.num_workers, i, 3, os.getenv('WORKER' + str(i + 1) + '_KEY'),
                       i < self.num_evil, int(os.getenv('WORKER' + str(i + 1) + '_PRICE'))))
            self.worker_dict[i] = self.workers[i].account.address
            self.worker_bid_dict[self.workers[i].account.address] = self.workers[i].bid
            self.workers[i].join_task(self.requester.get_contract_address())

        self.requester.start_task()

        for round in range(self.num_rounds):
            for idx, worker in enumerate(self.workers):
                # if round >0:
                #     if idx >= self.k:
                #         break
                worker.train(round)
                # print(worker.train)

            # starting eval phase
            for idx, worker in enumerate(self.workers):
                avg_dicts, topK_dicts, unsorted_scores = worker.evaluate(round)
                # unsorted_scores = [score[0].cpu().item() for score in unsorted_scores]
                unsorted_scores = [score[0].cpu().item() for score in unsorted_scores]
                unsorted_scores.insert(idx, -1)
                unsorted_scores = (idx, unsorted_scores)
                self.requester.push_scores(unsorted_scores)
                worker.update_model(avg_dicts)

            overall_scores = self.requester.calc_overall_scores(self.requester.get_score_matrix(), self.num_workers)
            top_k_addresses, top_k_scores = self.requester.compute_top_k(list(self.worker_dict.values()),
                                                                         overall_scores)
            top_k_scores = [int(i * 1000) for i in top_k_scores]
            print("开始调用反向拍卖。。。")
            self.requester.reverse_auction(top_k_scores, top_k_addresses, self.worker_bid_dict)
            print("反向拍卖完成，开始获取反向拍卖后结果...")
            workerScores = self.requester.getWorkerScores()
            print("当前是第", round, "轮", "选举出的工人是:", workerScores)
            committeeScores = self.requester.getCommitteeScores()
            print("当前是第", round, "轮", "选举出的委员会是:", committeeScores)
            print("开始分配奖励...")
            self.requester.distribute_rewards()

            print("开始验证，根据当前的round做kecacha256验证和区块链的bytesdata是否一致。。。")
            byteHash = Web3.solidityKeccak(['uint8'], [round + 1])
            res = self.requester.verifyRound(byteHash)
            print("验证结果为:", res)
            print("Distributed rewards. Next round starting soon...")
            self.requester.next_round()
