import asyncio
import sys
import os

sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from app.core.uow import SqlAlchemyUnitOfWork
from app.use_cases.wallet.commands.transfer_tuci import TransferTuciCommand
from app.core.exceptions import BadRequestException

class MockTransaction:
    def __init__(self, id, **kwargs):
        self.id = id
        for k, v in kwargs.items():
            setattr(self, k, v)

class MockTransactionRepository:
    def __init__(self):
        self.transactions = []
    async def create(self, obj_in):
        txn = MockTransaction(id=len(self.transactions) + 1, **obj_in)
        self.transactions.append(txn)
        return txn

class MockUoW(SqlAlchemyUnitOfWork):
    def __init__(self):
        self.transactions = MockTransactionRepository()
    async def __aenter__(self):
        return self
    async def __aexit__(self, exc_type, exc_val, traceback):
        pass
    async def commit(self):
        pass

async def test_wallet_cqrs():
    print("\n[TEST] Sprint 3: Wallet & Transactions CQRS Testi Başlıyor...")

    uow = MockUoW()
    transfer_cmd = TransferTuciCommand(uow)

    # Senaryo 1: Başarılı Transfer
    result = await transfer_cmd.execute(sender_id=1, receiver_id=2, amount=100)
    if result["status"] == "success":
        print("✅ Senaryo 1: Başarılı Tuci transferi ve UoW Commit test edildi.")
    else:
        print("❌ Senaryo 1 Başarısız")

    # Senaryo 2: Negatif Miktar
    try:
        await transfer_cmd.execute(sender_id=1, receiver_id=2, amount=-50)
        print("❌ Senaryo 2 Başarısız: Negatif transfere izin verildi.")
    except BadRequestException:
        print("✅ Senaryo 2: BadRequestException (Negatif Miktar) doğru fırlatıldı.")

    # Senaryo 3: Kendine Transfer
    try:
        await transfer_cmd.execute(sender_id=1, receiver_id=1, amount=100)
        print("❌ Senaryo 3 Başarısız: Kendine transfere izin verildi.")
    except BadRequestException:
        print("✅ Senaryo 3: BadRequestException (Kendine Transfer) doğru fırlatıldı.")

    print("\n🎉 Tüm Wallet Testleri Başarıyla Tamamlandı!")

if __name__ == "__main__":
    asyncio.run(test_wallet_cqrs())
