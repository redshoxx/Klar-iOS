from datetime import date, datetime
from typing import Literal
from uuid import UUID
from pydantic import BaseModel, ConfigDict, Field, field_validator, EmailStr

class StrictModel(BaseModel):
    model_config = ConfigDict(extra='forbid')

class TaskData(StrictModel):
    title: str = Field(min_length=1, max_length=200)
    completed: bool = False
    due_at: datetime | None = None
    priority: Literal['niedrig', 'mittel', 'hoch'] = 'mittel'
    project: str = Field(default='', max_length=100)
    notes: str = Field(default='', max_length=4000)
    repeat: Literal['nie', 'taeglich', 'woechentlich', 'monatlich'] = 'nie'

class TransactionData(StrictModel):
    title: str = Field(min_length=1, max_length=200)
    amount_cents: int = Field(ge=-100000000, le=100000000)
    category: str = Field(min_length=1, max_length=80)
    booked_at: datetime
    merchant: str = Field(default='', max_length=200)
    notes: str = Field(default='', max_length=4000)

class RecurringData(StrictModel):
    title: str = Field(min_length=1, max_length=200)
    amount_cents: int = Field(ge=0, le=100000000)
    category: str = Field(min_length=1, max_length=80)
    kind: Literal['fixkosten', 'abo']
    cadence: Literal['woechentlich', 'monatlich', 'jaehrlich'] = 'monatlich'
    next_due: date
    reminder_days: int = Field(default=3, ge=0, le=30)
    active: bool = True

class BudgetData(StrictModel):
    category: str = Field(min_length=1, max_length=80)
    monthly_limit_cents: int = Field(ge=0, le=100000000)

class ShoppingListData(StrictModel):
    name: str = Field(min_length=1, max_length=100)
    archived: bool = False

class ShoppingItemData(StrictModel):
    list_id: UUID
    name: str = Field(min_length=1, max_length=200)
    quantity: float = Field(gt=0, le=100000)
    unit: str = Field(default='Stk', max_length=20)
    unit_price_cents: int = Field(ge=0, le=100000000)
    checked: bool = False

class ProfileData(StrictModel):
    display_name: str = Field(default='', max_length=100)
    default_currency: Literal['EUR'] = 'EUR'

KIND_SCHEMAS = {
    'tasks': TaskData,
    'transactions': TransactionData,
    'recurring': RecurringData,
    'budgets': BudgetData,
    'shopping_lists': ShoppingListData,
    'shopping_items': ShoppingItemData,
    'profile': ProfileData,
}

class Credentials(StrictModel):
    email: EmailStr
    password: str = Field(min_length=12, max_length=200)

class RefreshRequest(StrictModel):
    refresh_token: str = Field(min_length=40)

class Mutation(StrictModel):
    kind: Literal['tasks','transactions','recurring','budgets','shopping_lists','shopping_items','profile']
    id: UUID
    base_version: int = Field(ge=0)
    deleted: bool = False
    data: dict = Field(default_factory=dict)

class PushRequest(StrictModel):
    mutations: list[Mutation] = Field(min_length=1, max_length=100)
